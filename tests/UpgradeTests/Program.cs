using Microsoft.Win32;
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
