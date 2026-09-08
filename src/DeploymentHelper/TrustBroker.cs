using System.Diagnostics;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

internal sealed class TrustBroker : IDisposable {
    [DllImport("kernel32.dll",SetLastError=true)]
    static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe,out uint pid);
    readonly NamedPipeServerStream pipe;
    StreamReader? reader;
    StreamWriter? writer;
    Process? process;
    bool settled;
    bool disposed;
    public bool Created {get;private set;}
    internal TrustBroker(NamedPipeServerStream stream){pipe=stream;}
    internal async Task Connect(uint expectedProcessId,CancellationToken cancellation){
        await pipe.WaitForConnectionAsync(cancellation);
        if(!GetNamedPipeClientProcessId(pipe.SafePipeHandle,out uint client)||client!=expectedProcessId)
            throw new IOException("Unexpected elevation pipe client.");
        // AutoFlush's setter flushes immediately. Never create a flushing writer
        // before connection and peer validation, including cancelled-UAC paths.
        reader=new(pipe,Encoding.ASCII,false,1024,true);
        writer=new(pipe,Encoding.ASCII,1024,true);
        writer.NewLine="\n";
        writer.AutoFlush=true;
    }
    internal async Task Handshake(bool acquire){
        if(await Read()!="READY")throw new IOException("Elevation helper failed validation.");
        string answer=await Command(acquire?"BEGIN":"OPEN");
        if(acquire&&answer!="CREATED"&&answer!="PREEXISTING")throw new IOException("Certificate acquisition failed: "+answer);
        if(!acquire&&answer!="OPENED")throw new IOException("Certificate cleanup session failed: "+answer);
        Created=answer=="CREATED";
    }
    public static async Task<TrustBroker> Open(string helper,bool acquire){
        if(Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(helper)))!=ProductIdentity.TrustHelperSha256)
            throw new InvalidDataException("Elevation helper does not match the signed build hash.");
        var sid=WindowsIdentity.GetCurrent().User!;
        var acl=new PipeSecurity();acl.SetAccessRuleProtection(true,false);
        acl.AddAccessRule(new PipeAccessRule(sid,PipeAccessRights.FullControl,AccessControlType.Allow));
        acl.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid,null),PipeAccessRights.ReadWrite,AccessControlType.Allow));
        string nonce=Guid.NewGuid().ToString("N");
        var stream=NamedPipeServerStreamAcl.Create("SmartZipModernTrust-"+nonce,PipeDirection.InOut,1,PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous|PipeOptions.FirstPipeInstance,4096,4096,acl);
        var broker=new TrustBroker(stream);
        try{
            broker.process=Process.Start(new ProcessStartInfo(helper){UseShellExecute=true,Verb="runas",
                Arguments="--session "+nonce+" "+Environment.ProcessId,WorkingDirectory=Environment.GetFolderPath(Environment.SpecialFolder.System)});
            if(broker.process==null)throw new IOException("Certificate helper did not start.");
            using var timeout=new CancellationTokenSource(TimeSpan.FromMinutes(3));
            var connect=broker.Connect((uint)broker.process.Id,timeout.Token);
            var exited=broker.process.WaitForExitAsync(timeout.Token);
            if(await Task.WhenAny(connect,exited)==exited&&!connect.IsCompleted){
                await exited;timeout.Cancel();
                try{await connect;}catch(OperationCanceledException){}
                throw new IOException("Certificate helper exited before connecting. Exit code: "+broker.process.ExitCode);
            }
            await connect;await broker.Handshake(acquire);return broker;
        }catch{broker.Dispose();throw;}
    }
    async Task<string> Read(){using var timeout=new CancellationTokenSource(TimeSpan.FromMinutes(3));return await (reader??throw new InvalidOperationException("Certificate pipe is not initialized.")).ReadLineAsync(timeout.Token)??throw new IOException("Certificate helper disconnected.");}
    async Task<string> Command(string command){await (writer??throw new InvalidOperationException("Certificate pipe is not initialized.")).WriteLineAsync(command);return await Read();}
    public async Task Commit(){if(await Command("COMMIT")!="COMMITTED")throw new IOException("Certificate commit failed.");settled=true;}
    public async Task Rollback(){if(settled)return;if(await Command("ROLLBACK")!="ROLLEDBACK")throw new IOException("Certificate rollback failed.");settled=true;}
    public async Task<string> Release(bool owned){string result=await Command(owned?"RELEASE_OWNED":"RELEASE_SHARED");if(result!="REMOVED"&&result!="RETAINED")throw new IOException("Certificate removal failed: "+result);settled=true;return result;}
    public void Dispose(){
        if(disposed)return;disposed=true;
        // Close the transport first: no pending command may be flushed during
        // cancellation, and a cleanup exception must not replace the real error.
        pipe.Dispose();
        try{writer?.Dispose();}catch(IOException){}catch(InvalidOperationException){}
        reader?.Dispose();
        // Disconnect rolls back newly created trust. Never kill the broker.
        if(process!=null){try{process.WaitForExit(10000);}catch(InvalidOperationException){}process.Dispose();}
    }
}
