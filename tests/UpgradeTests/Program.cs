using Microsoft.Win32;
if(args.SequenceEqual(new[]{"--read-only-installed-health"})){
    var packages=new Windows.Management.Deployment.PackageManager().FindPackagesForUser("")
        .Where(p=>p.Id.Name=="SmartZip.Modern"&&p.Id.Publisher=="CN=SmartZip Modern Evaluation").ToArray();
    if(packages.Length!=1)throw new IOException("Expected one installed test package for read-only diagnosis.");
    var package=packages[0];var health=PackageHealth.Read(package.Status);
    Console.WriteLine(package.Id.FullName+": "+health);
    try{Console.WriteLine("ExternalLocation="+package.EffectiveExternalLocation.Path);}
    catch(Exception ex){Console.WriteLine($"ExternalLocation unavailable: 0x{ex.HResult:X8}; {ex.Message}");}
    try{health.RequireHealthy(package.Id.FullName);Console.WriteLine("READONLY: healthy package accepted.");}
    catch(PackageHealthException){Console.WriteLine("READONLY: unhealthy package blocked; no COM activation, repair, registration or certificate changes.");}
    return;
}
static void Check(bool ok){if(!ok)throw new Exception("Upgrade safety regression.");}
static void Reject(Action action){try{action();}catch(Exception e)when(e is IOException or UpgradeBaselineException){return;}throw new Exception("Unsafe upgrade was accepted.");}
UpgradePolicy.RequireNewer("0.1.0.8","0.1.0.9");
foreach(var pair in new[]{("0.1.0.8","0.1.0.8"),("0.1.0.9","0.1.0.8"),("0.1.0.7","0.1.0.9")})
    Reject(()=>UpgradePolicy.RequireNewer(pair.Item1,pair.Item2));
foreach(var invalid in new[]{"1.2.3","../0.1.0.8","v0.1.0.8","0.01.0.8","65536.0.0.0","-1.0.0.0"})Reject(()=>UpgradePolicy.VersionNumber(invalid));
const string nonce="0123456789abcdef0123456789abcdef";
var old=new PreviousInstall("0.1.0.8",nonce,true,new string('A',64));
var receipt=new Journal(nonce,true,"test-sid",@"C:\测试\SmartZip",old);
UpgradePolicy.RequireReceipt(receipt,@"C:\测试\SmartZip","test-sid");
Reject(()=>UpgradePolicy.RequireReceipt(receipt,@"D:\SmartZip","test-sid"));
Reject(()=>UpgradePolicy.RequireReceipt(receipt,@"C:\测试\SmartZip","other-sid"));
Reject(()=>UpgradePolicy.RequireReceipt(receipt with{Nonce="../bad"},@"C:\测试\SmartZip","test-sid"));
Check(JournalJson.Deserialize(JournalJson.Serialize(receipt))==receipt);
var values=new[]{new BackupValue("unicode",RegistryValueKind.String,new[]{"中文 & ()"}),new BackupValue("dword",RegistryValueKind.DWord,new[]{"-1"}),new BackupValue("qword",RegistryValueKind.QWord,new[]{"-2"}),new BackupValue("multi",RegistryValueKind.MultiString,new[]{"a","中"}),new BackupValue("expand",RegistryValueKind.ExpandString,new[]{"%LOCALAPPDATA%"}),new BackupValue("binary",RegistryValueKind.Binary,new[]{"AAH/"})};
var backup=new UpgradeBackupData(nonce,new[]{new BackupKey(UpgradeBackup.StateKey,values),new BackupKey(UpgradeBackup.UninstallKey,Array.Empty<BackupValue>())},
    new[]{"unins000.exe","unins000.dat","unins000.msg",".install-transaction","shortcut-settings","shortcut-uninstall","shortcut-updates"}.Select(n=>new BackupFile(n,n=="unins000.msg"?null:new byte[]{0,1,255})).ToArray());
UpgradeBackup.ValidateData(backup,nonce);
var encoded=UpgradeBackup.Serialize(backup);Check(UpgradeBackup.Serialize(UpgradeBackup.Deserialize(encoded))==encoded);
Check((int)values[1].Value()==-1&&(long)values[2].Value()==-2&&((byte[])values[5].Value()).SequenceEqual(new byte[]{0,1,255}));
Reject(()=>UpgradeBackup.ValidateData(backup,"another-nonce"));
Reject(()=>UpgradeBackup.ValidateData(backup with{Keys=new[]{new BackupKey(@"Software\Other",values)}},nonce));
Reject(()=>UpgradeBackup.ValidateData(backup with{Files=new[]{new BackupFile(@"..\outside",new byte[]{1})}},nonce));
Reject(()=>UpgradeBackup.DirectoryPath(@"C:\SmartZip",@"..\outside"));
Console.WriteLine("PASS newer-version/identity/path guards, ownership preservation, source-generated journal and exact backup scope");
// Exercise the production transaction rollback ordering with injected partial failures.
foreach(bool owned in new[]{false,true})foreach(string failure in new[]{"stage","package","verify"}){
    var tx=new Transaction();bool oldFiles=true,newFiles=false;string package="old";bool certOwned=owned;string config="user configuration";
    try{
        await tx.Step("stage",()=>{newFiles=true;if(failure=="stage")throw new IOException("injected");return Task.CompletedTask;},()=>{Check(package=="old");newFiles=false;return Task.CompletedTask;});
        await tx.Step("package",()=>{package="new";if(failure=="package")throw new IOException("injected");return Task.CompletedTask;},()=>{package="old";return Task.CompletedTask;});
        throw new IOException("verification failed");
    }catch(IOException){await tx.Rollback();}
    Check(oldFiles&&!newFiles&&package=="old"&&certOwned==owned&&config=="user configuration");
}
{
    var tx=new Transaction();bool newFiles=true;
    await tx.Step("stage",()=>Task.CompletedTask,()=>{newFiles=false;return Task.CompletedTask;});
    await tx.Step("package",()=>Task.CompletedTask,()=>throw new IOException("Windows refuses restoration"));
    bool refused=false;try{await tx.Rollback();}catch(Exception){refused=true;}
    Check(refused&&newFiles);
}
Console.WriteLine("PASS 6 upgrade failure cases; failed package restore keeps backing files. No registry/package/certificate mutations.");

// Same version is not enough: exercise the actual health and restoration guards.
var healthy=new PackageHealth(true,false,false,false,false,false,false);
healthy.RequireHealthy("fixture");
for(int mask=0;mask<128;mask++){
    var health=new PackageHealth((mask&1)!=0,(mask&2)!=0,(mask&4)!=0,(mask&8)!=0,
        (mask&16)!=0,(mask&32)!=0,(mask&64)!=0);
    Check(health.IsHealthy==(mask==1));
    if(mask!=1)Reject(()=>health.RequireHealthy("fixture"));
}
foreach(int count in new[]{0,1,2})foreach(bool matches in new[]{false,true})foreach(bool ok in new[]{false,true})
    Check(UpgradePolicy.NeedsPackageRestore(count,matches,ok)==!(count==1&&matches&&ok));
foreach(var outcome in new[]{"healthy","still-unhealthy","throws"}){
    var tx=new Transaction();bool files=true,restored=false,complete=false;
    var health=healthy with{NeedsRemediation=true,Modified=true};
    await tx.Step("files",()=>Task.CompletedTask,()=>{files=false;return Task.CompletedTask;});
    await tx.Step("package",()=>Task.CompletedTask,()=>{
        if(UpgradePolicy.NeedsPackageRestore(1,true,health.IsHealthy)){
            restored=true;
            if(outcome=="throws")throw new IOException("Windows refuses restoration");
            if(outcome=="healthy")health=healthy;
        }
        health.RequireHealthy("old-version");return Task.CompletedTask;
    });
    try{await tx.Rollback();complete=true;}catch(Exception){ }
    Check(restored&&complete==(outcome=="healthy")&&files==(outcome!="healthy"));
}
var busy=new System.Runtime.InteropServices.COMException("fixture",DeploymentFailure.PackagesInUse);
Check(DeploymentFailure.UserMessage(busy)!.Contains("0x80073D02"));
Check(DeploymentFailure.UserMessage(new IOException("wrapper",busy))!.Contains("0x80073D02"));
Check(DeploymentFailure.UserMessage(new AggregateException(busy))!.Contains("0x80073D02"));
Check(DeploymentFailure.UserMessage(new RollbackIncompleteException(busy,new PackageHealthException("fixture")))!.Contains("回滚也未能"));
Check(DeploymentFailure.UserMessage(new PackageHealthException("fixture"))!.Contains("状态异常"));
Check(DeploymentFailure.UserMessage(new IOException("other error"))==null);
Console.WriteLine("PASS 128 package-health states, 12 restore decisions, same-version remediation and failed-restore retention, busy/rollback Chinese error priority. No package mutations.");
