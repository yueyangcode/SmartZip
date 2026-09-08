using System.Diagnostics;
using System.IO.Pipes;
using System.Text;
using System.Reflection;
using System.Security.Principal;
using Microsoft.Win32;

// Uses the real broker code and Windows pipes with a separate child process.
// Peers are protocol fixtures, never a certificate/Package installer.
static void Check(bool ok,string message){if(!ok)throw new Exception(message);}
static NamedPipeServerStream Server(string name)=>new(name,PipeDirection.InOut,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous|PipeOptions.FirstPipeInstance);
static Process Peer(string name,string mode){
    var start=new ProcessStartInfo(Environment.ProcessPath!){UseShellExecute=false,CreateNoWindow=true};
    if(Path.GetFileNameWithoutExtension(start.FileName)=="dotnet")start.ArgumentList.Add(Assembly.GetExecutingAssembly().Location);
    start.ArgumentList.Add("--peer");start.ArgumentList.Add(name);start.ArgumentList.Add(mode);
    return Process.Start(start)!;
}
if(args.Length==2&&args[0]=="--native-readonly"){
    using var user=WindowsIdentity.GetCurrent();
    using var policy=Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System");
    Check(new WindowsPrincipal(user).IsInRole(WindowsBuiltInRole.Administrator)&&policy?.GetValue("EnableLUA") is int lua&&lua==0,
        "Read-only native probe requires the already-admin UAC-off development session; do not elevate for this probe.");
    using var broker=await TrustBroker.Open(args[1],false); // OPEN, never BEGIN or RELEASE
    await broker.Rollback(); // native flags are all false: closes session, no trust-store changes
    Console.WriteLine("PASS actual pinned native helper: authenticated OPEN/ROLLBACK, no certificate or package writes");
    return;
}
if(args.Length==3&&args[0]=="--peer"){
    try{
        using var pipe=new NamedPipeClientStream(".",args[1],PipeDirection.InOut,PipeOptions.Asynchronous);
        await pipe.ConnectAsync(5000);
        using var reader=new StreamReader(pipe,Encoding.ASCII,false,1024,true);
        using var writer=new StreamWriter(pipe,Encoding.ASCII,1024,true){AutoFlush=true,NewLine="\n"};
        await writer.WriteLineAsync(args[2]=="bad-ready"?"INVALID":"READY");
        if(args[2]=="disconnect-ready")return;
        string? begin=await reader.ReadLineAsync();if(begin==null)return;
        Check(begin=="BEGIN"||begin=="OPEN","unexpected command");
        await writer.WriteLineAsync(args[2]=="bad-answer"?"ERROR":begin=="OPEN"?"OPENED":args[2]=="preexisting"?"PREEXISTING":"CREATED");
        if(args[2]=="disconnect-acquired")return;
        string? decision=await reader.ReadLineAsync();if(decision==null)return;
        await writer.WriteLineAsync(decision switch{"COMMIT"=>"COMMITTED","ROLLBACK"=>"ROLLEDBACK","RELEASE_OWNED"=>"REMOVED","RELEASE_SHARED"=>"RETAINED",_=>"ERROR"});
    }catch(IOException){} // server rejection deliberately breaks the pipe
    return;
}
// This reproduces the exact original bug without editing any product code.
{
    using var pipe=Server("SmartZipRegression-"+Guid.NewGuid().ToString("N"));
    var writer=new StreamWriter(pipe,Encoding.ASCII,1024,true);
    bool reproduced=false;try{writer.AutoFlush=true;}catch(InvalidOperationException){reproduced=true;}
    pipe.Dispose();try{writer.Dispose();}catch(InvalidOperationException){}
    Check(reproduced,"original disconnected AutoFlush exception was not reproduced");
    Console.WriteLine("PASS original test3 fault reproduced on a real disconnected pipe");
}
{
    string name="SmartZipRegression-"+Guid.NewGuid().ToString("N");
    var broker=new TrustBroker(Server(name)); // must not flush before connection
    using var cancel=new CancellationTokenSource(100);
    bool cancelled=false;try{await broker.Connect((uint)Environment.ProcessId,cancel.Token);}catch(OperationCanceledException){cancelled=true;}
    broker.Dispose();broker.Dispose();
    using var reusable=Server(name); // verifies the first instance handle was released
    Check(cancelled,"unconnected wait did not cancel");
    Console.WriteLine("PASS constructor/cancel/dispose twice/recreate same pipe");
}
foreach(string scenario in new[]{"commit","rollback","preexisting","release-owned","release-shared","wrong-pid","bad-ready","bad-answer","disconnect-ready","disconnect-acquired"}){
    string name="SmartZipRegression-"+Guid.NewGuid().ToString("N");
    using var broker=new TrustBroker(Server(name));using var peer=Peer(name,scenario);
    bool expectedFailure=scenario is "wrong-pid" or "bad-ready" or "bad-answer" or "disconnect-ready" or "disconnect-acquired",failed=false;
    try{
        using var deadline=new CancellationTokenSource(5000);
        await broker.Connect(scenario=="wrong-pid"?uint.MaxValue:(uint)peer.Id,deadline.Token);
        bool acquire=!scenario.StartsWith("release-");
        await broker.Handshake(acquire).WaitAsync(TimeSpan.FromSeconds(5));
        if(acquire)Check(broker.Created==(scenario!="preexisting"),"wrong ownership from handshake");
        if(scenario=="commit")await broker.Commit();
        else if(scenario=="release-owned")Check(await broker.Release(true)=="REMOVED","wrong release response");
        else if(scenario=="release-shared")Check(await broker.Release(false)=="RETAINED","wrong retain response");
        else await broker.Rollback().WaitAsync(TimeSpan.FromSeconds(5));
    }catch(IOException){failed=true;}
    finally{broker.Dispose();}
    await peer.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));
    Check(peer.ExitCode==0,"peer failed");Check(failed==expectedFailure,"unexpected outcome: "+scenario);
    using var reusable=Server(name);
    Console.WriteLine("PASS real cross-process pipe: "+scenario+"; handles released");
}
