using System.Diagnostics;
using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

if(args.Length==1&&args[0]=="--dialog-smoke"){
    bool finished=false;
    UpdateDialog.Run(async operation=>{
        operation.Report("离线界面自检：不联网、不下载、不安装。",50);
        await Task.Delay(600,operation.Token);operation.BeginInstall();
        operation.Report("自检完成：没有执行安装。",100);await Task.Delay(300);finished=true;
    },"SmartZip 离线进度窗口自检");
    if(!finished)throw new Exception("Native dialog callback did not complete.");
    Console.WriteLine("PASS native progress dialog, timer, progress updates and completion callback; no network/files/install actions.");return;
}

static void Check(bool ok,string label){if(!ok)throw new Exception(label);}
static void Reject(Action action){try{action();}catch(Exception e)when(e is IOException or OperationCanceledException){return;}throw new Exception("Unsafe updater action accepted.");}
static async Task RejectAsync(Func<Task> action){try{await action();}catch(Exception e)when(e is IOException or OperationCanceledException){return;}throw new Exception("Unsafe download accepted.");}
byte[] bytes={0,1,2,255};string hash=Convert.ToHexString(SHA256.HashData(bytes));
string json="""
{"draft":false,"prerelease":false,"tag_name":"v0.1.0.11","body":"测试更新说明","assets":[{"name":"SmartZipSetup-0.1.0.11-x64.exe","state":"uploaded","size":4,"digest":"sha256:HASH","browser_download_url":"https://github.com/yueyangcode/SmartZip/releases/download/v0.1.0.11/SmartZipSetup-0.1.0.11-x64.exe"}]}
""".Replace("HASH",hash);
var release=UpdateRelease.Parse(json,"0.1.0.10")!;
Check(release.Version=="0.1.0.11"&&release.Size==4,"release");
Check(UpdateRelease.Parse(json,"0.1.0.11")==null&&UpdateRelease.Parse(json,"0.1.0.12")==null,"same/downgrade");
Check(UpdateRelease.Parse(json.Replace("\"draft\":false","\"draft\":true"),"0.1.0.10")==null,"draft");
Check(UpdateRelease.Parse(json.Replace("\"prerelease\":false","\"prerelease\":true"),"0.1.0.10")==null,"prerelease");
foreach(var bad in new[]{json.Replace("sha256:","md5:"),json.Replace("github.com/yueyangcode","github.com/other"),json.Replace("\"size\":4","\"size\":134217729"),json.Replace("uploaded","new"),json.Replace("x64.exe\",\"state","arm64.exe\",\"state")})Reject(()=>UpdateRelease.Parse(bad,"0.1.0.10"));
foreach(var v in new[]{"v1.2.3","v0.01.0.11","v65536.0.0.0","v0.1.0.11-test","../../evil"})Reject(()=>UpdateRelease.ParseVersion(v));
foreach(var url in new[]{"http://release-assets.githubusercontent.com/a","https://release-assets.githubusercontent.com.evil.example/a","https://user@release-assets.githubusercontent.com/a","https://release-assets.githubusercontent.com:444/a","file:///C:/a.exe","https://github.com/other/a"})Check(!UpdateRelease.DownloadRedirectAllowed(new Uri(url)),"redirect rejection");
using(var output=new MemoryStream()){await UpdateDownload.CopyVerified(new MemoryStream(bytes),output,4,hash,_=>{},CancellationToken.None);Check(output.ToArray().SequenceEqual(bytes),"verified bytes");}
await RejectAsync(()=>UpdateDownload.CopyVerified(new MemoryStream(bytes),new MemoryStream(),5,hash,_=>{},CancellationToken.None));
await RejectAsync(()=>UpdateDownload.CopyVerified(new MemoryStream(bytes),new MemoryStream(),3,hash,_=>{},CancellationToken.None));
await RejectAsync(()=>UpdateDownload.CopyVerified(new MemoryStream(bytes),new MemoryStream(),4,new string('A',64),_=>{},CancellationToken.None));
using(var cancel=new CancellationTokenSource()){cancel.Cancel();await RejectAsync(()=>UpdateDownload.CopyVerified(new MemoryStream(bytes),new MemoryStream(),4,hash,_=>{},cancel.Token));}
foreach(var bad in new[]{"http://release-assets.githubusercontent.com/a","https://evil.example/a"}){
    var handler=new FakeHandler(_=>new(HttpStatusCode.Redirect){Headers={Location=new Uri(bad)}});using var http=new HttpClient(handler);
    await RejectAsync(async()=>{using var response=await UpdateDownload.Open(http,release,CancellationToken.None);});Check(handler.Calls==1,"bad redirect followed");
}
{
    var handler=new FakeHandler(n=>n==1?new(HttpStatusCode.Redirect){Headers={Location=new Uri("https://release-assets.githubusercontent.com/fixture")}}:new(HttpStatusCode.OK){Content=new ByteArrayContent(bytes)});
    using var http=new HttpClient(handler);using var result=await UpdateDownload.Open(http,release,CancellationToken.None);Check(handler.Calls==2,"allowed redirect");
}
{
    using var http=new HttpClient(new FakeHandler(_=>new(HttpStatusCode.Redirect){Headers={Location=new Uri("https://release-assets.githubusercontent.com/loop")}}));
    await RejectAsync(async()=>{using var response=await UpdateDownload.Open(http,release,CancellationToken.None);});
}
var now=DateTime.UtcNow;Check(!UpdateCheck.Due(now,now)&&UpdateCheck.Due(now.AddDays(-1),now)&&UpdateCheck.Due(now.AddDays(1),now),"daily clock guard");
using(var operation=new UpdateOperation()){operation.Cancel();Reject(operation.BeginInstall);}
using(var operation=new UpdateOperation()){operation.BeginInstall();operation.Cancel();Check(!operation.Token.IsCancellationRequested&&!operation.Snapshot.CanCancel,"cancel during commit");}
var start=UpdateCheck.InstallerStart(@"C:\测试 & ()\setup.exe",@"D:\软件 & ()\SmartZip",@"C:\logs\update.log");
Check(start.UseShellExecute&&start.Verb==""&&start.FileName.EndsWith("setup.exe")&&start.ArgumentList.Contains(@"/DIR=D:\软件 & ()\SmartZip")&&start.ArgumentList.Contains("/NORESTART")&&start.ArgumentList.Contains("/NOFORCECLOSEAPPLICATIONS"),"installer launch policy");
Console.WriteLine("PASS release/channel/version, canonical assets, redirect allowlist, streaming hash/size/cancellation, daily checks, consent cancellation and silent arguments. HTTP responses are in memory; no network.");
if(args.Length!=4)throw new Exception("Expected signed test artifact, version, CER and native activity test paths.");
using var cert=new X509Certificate2(File.ReadAllBytes(args[2]));string certHash=Convert.ToHexString(SHA256.HashData(cert.RawData));
using(var pin=new FileStream(args[0],FileMode.Open,FileAccess.Read,FileShare.Read)){
    UpdateSignature.Verify(args[0],args[1],cert.Subject,certHash,cert.Subject==cert.Issuer);
    Reject(()=>UpdateSignature.Verify(args[0],args[1],cert.Subject,new string('A',64),true));
    Reject(()=>UpdateSignature.Verify(args[0],"99.0.0.0",cert.Subject,certHash,true));
}
string folder=Path.Combine(Path.GetDirectoryName(args[3])!,"updater-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
string modified=Path.Combine(folder,"tampered.exe"),lease=Path.Combine(folder,"activity.lock"),echoFile=Path.Combine(folder,"arguments.txt");
try {
    File.Copy(args[0],modified);using(var f=new FileStream(modified,FileMode.Open,FileAccess.ReadWrite)){f.Position=1024;int value=f.ReadByte();f.Position=1024;f.WriteByte((byte)(value^1));}
    Reject(()=>UpdateSignature.Verify(modified,args[1],cert.Subject,certHash,true));
    var nativeStart=new ProcessStartInfo(args[3]){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardInput=true};
    using(var layout=Process.Start(nativeStart)!){string line=await layout.StandardOutput.ReadToEndAsync();await layout.WaitForExitAsync();var d=UpdateDialog.Layout();var s=UpdateSignature.Layout();Check(line.Trim()==$"{d.Config} {d.Button} {s.Data} {s.File}","native struct layout mismatch: "+line);}
    nativeStart.ArgumentList.Add(lease);
    using(var active=Process.Start(nativeStart)!){
        Check(await active.StandardOutput.ReadLineAsync()=="HELD","native extraction lease");
        using(var another=new FileStream(lease,FileMode.Open,FileAccess.Read,FileShare.Read)){}
        using(var cancel=new CancellationTokenSource(200)){await RejectAsync(async()=>{using var gate=await UpdateActivity.WaitForIdle(lease,cancel.Token,()=>{});});}
        await active.StandardInput.WriteLineAsync("release");await active.WaitForExitAsync();Check(active.ExitCode==0,"native lease exit");
    }
    using(var exclusive=await UpdateActivity.WaitForIdle(lease,CancellationToken.None,()=>{})){
        using var blocked=Process.Start(nativeStart)!;await blocked.WaitForExitAsync();Check(blocked.ExitCode==3,"new extraction raced install");
    }
    var echo=UpdateCheck.InstallerStart(args[3],@"D:\中文 空格 & () 📦\SmartZip",@"C:\中文 日志\update.log");
    var expectedArgs=echo.ArgumentList.ToArray();echo.ArgumentList.Insert(0,echoFile);echo.ArgumentList.Insert(0,"--echo");
    using var pinnedEcho=new FileStream(args[3],FileMode.Open,FileAccess.Read,FileShare.Read);
    using(var process=Process.Start(echo)!){await process.WaitForExitAsync();Check(process.ExitCode==0,"native argument echo");}
    Check(File.ReadAllLines(echoFile,System.Text.Encoding.Unicode).SequenceEqual(expectedArgs),"ShellExecute argument round-trip");
}finally{if(File.Exists(modified))File.Delete(modified);if(File.Exists(lease))File.Delete(lease);if(File.Exists(echoFile))File.Delete(echoFile);Directory.Delete(folder,false);}
Console.WriteLine("PASS actual WinVerifyTrust/pinned verified signer, wrong signer/version/tamper rejection; x64 ABI and real native/.NET shared/exclusive activity locking. No installer was executed; no certificate/package writes.");
internal sealed class FakeHandler(Func<int,HttpResponseMessage> respond):HttpMessageHandler {
    internal int Calls;
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancel)=>Task.FromResult(respond(++Calls));
}
internal static class ProductIdentity {
    internal const string Version="0.1.0.10",Publisher="TEST-ONLY",CertificateSha256="TEST-ONLY";
    internal static readonly bool TestSigned=true;
}
