using Microsoft.Win32;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.Principal;
using System.Text;
using System.Xml.Linq;
using Windows.Management.Deployment;

internal static class Program {
    const string StateKey=@"Software\SmartZipModern";
    const string Clsid="{C12835D9-8B49-48D9-AE52-5E66D31209E1}";
    static readonly string Source=AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
    static string AppRoot=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","SmartZip");
    static string Target=>Path.Combine(AppRoot,"Versions",ProductIdentity.Version);
    static readonly string Receipt=Path.Combine(Source,"transaction.json");
    static readonly string Log=Path.Combine(Path.GetTempPath(),"SmartZip-"+ProductIdentity.Version+"-"+Environment.ProcessId+".log");
    static void Note(string message)=>File.AppendAllText(Log,DateTimeOffset.Now+" "+message+Environment.NewLine,Encoding.UTF8);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int MessageBoxW(IntPtr h,string text,string caption,uint type);
    [DllImport("shell32.dll")] static extern void SHChangeNotify(uint e,uint f,IntPtr a,IntPtr b);
    [DllImport("ole32.dll")] static extern int CoInitializeEx(IntPtr p,uint flags);
    [DllImport("ole32.dll")] static extern void CoUninitialize();
    [DllImport("ole32.dll")] static extern int CoCreateInstance(ref Guid clsid,IntPtr outer,uint context,ref Guid iid,out IntPtr value);
    static string Marker=>Path.Combine(AppRoot,".install-transaction");
    static void Save(Journal j)=>File.WriteAllText(Receipt,JournalJson.Serialize(j));
    static Journal ReadJournal(){
        var j=JournalJson.Deserialize(File.ReadAllText(Receipt));
        UpgradePolicy.RequireReceipt(j,AppRoot,WindowsIdentity.GetCurrent().User!.Value);
        if(j.Previous!=null)UpgradePolicy.RequireNewer(j.Previous.Version,ProductIdentity.Version);
        return j;
    }
    static IEnumerable<Windows.ApplicationModel.Package> Packages(PackageManager m)=>m.FindPackagesForUser("").Where(p=>p.Id.Name==ProductIdentity.Name&&p.Id.Publisher==ProductIdentity.Publisher);
    static string VersionOf(Windows.ApplicationModel.Package p)=>$"{p.Id.Version.Major}.{p.Id.Version.Minor}.{p.Id.Version.Build}.{p.Id.Version.Revision}";

    static async Task<int> Main(string[] args){
        try{
            if(args.Length<1)throw new ArgumentException("Missing operation.");
            for(int i=1;i<args.Length;i++){
                if(args[i]=="--no-ui")continue;
                if(args[i]=="--root" && i+1<args.Length && new[]{"preflight","prepare","commit","rollback","finalize"}.Contains(args[0])){
                    AppRoot=InstallPath.Validate(args[++i]);continue;
                }
                throw new ArgumentException("Unexpected argument.");
            }
            if(args[0]=="uninstall"){
                AppRoot=InstallPath.Validate(Path.GetFullPath(Path.Combine(Source,"..","..")));
            }
            switch(args[0]){
                case "check-updates":await UpdateCheck.Run(args.Contains("--no-ui"),Note,text=>MessageBoxW(IntPtr.Zero,text,"SmartZip 更新",0x24)==6);break;
                case "inspect":Inspect(Source);break;
                case "inspect-runtime":
                    Inspect(Source);
                    var options=new AddPackageOptions{ExternalLocationUri=new Uri(Source+Path.DirectorySeparatorChar)};
                    if(options.ExternalLocationUri==null)throw new IOException("WinRT options round-trip failed.");
                    Note("READONLY_RUNTIME_OK packages="+Packages(new PackageManager()).Count());
                    break;
                case "preflight":Preflight();break;
                case "prepare":await Prepare();break;
                case "commit":Commit();break;
                case "finalize":FinalizeInstall();break;
                case "rollback":await RollbackPrepared();break;
                case "uninstall":await Uninstall();break;
                default:throw new ArgumentException("Unknown operation.");
            }return 0;
        }catch(Exception ex){Note(ex.ToString());if(!args.Contains("--no-ui"))MessageBoxW(IntPtr.Zero,UserError(ex)+"\n\n日志文件：\n"+Log,"SmartZip 安装/卸载提示",0x10);return 1;}
    }
    static string UserError(Exception ex) {
        if (ex is UpgradeBaselineException or InstallDirectoryOccupiedException) return ex.Message;
        if (ex.Message == "This test build requires a clean project baseline. Uninstall the previous build first; existing files will not be overwritten.")
            return "检测到已安装的 SmartZip Modern 或上次安装残留。此测试版不支持覆盖安装。\n\n如果当前版本已能正常使用，无需重复安装。需要更换版本时，请先在“设置 → 应用 → 安装的应用”中卸载 SmartZip Modern，再重试。请勿手动删除安装目录。";
        return "操作未能完成。为避免破坏现有安装，请勿手动删除文件、补注册或修改证书。\n请将下方日志文件提供给开发者检查。\n错误代码：0x" + ex.HResult.ToString("X8");
    }
    static void RequirePerUser(){
        UserContext.Require(Note);
    }
    static void Fault(string stage){
        if(ProductIdentity.TestSigned&&ProductIdentity.FaultAt==stage)
            throw new IOException("故障注入测试："+stage+"；本安装包专用于测试失败回滚，不是正常安装包。");
    }
    static PreviousInstall? Preflight(){
        RequirePerUser();if(RuntimeInformation.OSArchitecture!=Architecture.X64||!OperatingSystem.IsWindowsVersionAtLeast(10,0,22621))throw new InvalidOperationException("Windows 11 x64 required.");
        using var key=Registry.CurrentUser.OpenSubKey(StateKey);
        using var uninstallState=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\{DA975784-DC84-48EF-9A47-F60C0C969280}_is1");
        var knownVersionPath=key?.GetValue("VersionPath") as string;
        var hasReceipt=knownVersionPath!=null && File.Exists(Path.Combine(knownVersionPath,"installed.json"));
        var packageExists=Packages(new PackageManager()).Any();
        var legacyRoot=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","SmartZip Modern");
        Note($"PREFLIGHT_ROOT={AppRoot}; Source={Source}; TargetDirectoryExists={Directory.Exists(AppRoot)}; TargetFileExists={File.Exists(AppRoot)}; LegacyDirectoryExists={Directory.Exists(legacyRoot)}; StateKeyExists={key!=null}; UninstallKeyExists={uninstallState!=null}; PackageExists={packageExists}; ReceiptExists={hasReceipt}");
        UpgradeBaseline.RequireCoherent(key!=null,packageExists,uninstallState!=null,hasReceipt);
        InstallPath.Validate(AppRoot);SafeParents(AppRoot);Inspect(Source);
        if(key!=null){
            string Read(string name)=>key.GetValue(name) as string??throw new UpgradeBaselineException("旧版产品状态缺少 "+name);
            var previous=Read("Version");UpgradePolicy.RequireNewer(previous,ProductIdentity.Version);
            var previousPath=Path.Combine(AppRoot,"Versions",previous);SafeTree(previousPath);
            string sid=WindowsIdentity.GetCurrent().User!.Value;
            var installed=JournalJson.Deserialize(File.ReadAllText(Path.Combine(previousPath,"installed.json")));
            UpgradePolicy.RequireReceipt(installed,AppRoot,sid);
            if(Read("Publisher")!=ProductIdentity.Publisher||Read("CertificateThumbprint")!=ProductIdentity.CertificateThumbprint||Read("UserSid")!=sid||
               !string.Equals(Read("VersionPath"),previousPath,StringComparison.OrdinalIgnoreCase)||
               key.GetValue("CertificateCreated") is not int owned||owned!=(installed.CertificateCreated?1:0)||
               !string.Equals((uninstallState!.GetValue("InstallLocation") as string)?.TrimEnd('\\'),AppRoot,StringComparison.OrdinalIgnoreCase)||
               uninstallState.GetValue("DisplayVersion") as string!=previous||
               !string.Equals(uninstallState.GetValue("UninstallString") as string,"\""+Path.Combine(AppRoot,"unins000.exe")+"\"",StringComparison.OrdinalIgnoreCase)||
               File.ReadAllText(Marker)!=installed.Nonce)
                throw new UpgradeBaselineException("旧版目录、签名身份、卸载入口或收据不一致。未修改旧版，请保留日志。");
            if(!File.Exists(Path.Combine(AppRoot,"unins000.exe"))||!File.Exists(Path.Combine(AppRoot,"unins000.dat")))
                throw new UpgradeBaselineException("旧版卸载程序不完整，不能安全覆盖升级。");
            if(File.Exists(Path.Combine(AppRoot,"recovery.json")))throw new UpgradeBaselineException("发现尚未解决的事务恢复记录，请先检查日志。");
            Inspect(previousPath,previous,false);VerifyRegistration(previous,previousPath);
            InstallPath.RequireUnused(Target);
            // Existing trust and its ownership lease remain untouched throughout upgrade.
            if(ProductIdentity.TestSigned){
            using var trusted=new X509Store(StoreName.TrustedPeople,StoreLocation.LocalMachine);
            trusted.Open(OpenFlags.ReadOnly|OpenFlags.OpenExistingOnly);
            if(!trusted.Certificates.Find(X509FindType.FindByThumbprint,ProductIdentity.CertificateThumbprint,false).OfType<X509Certificate2>()
                .Any(c=>Convert.ToHexString(SHA256.HashData(c.RawData))==ProductIdentity.CertificateSha256))
                throw new UpgradeBaselineException("旧版使用的测试证书信任已缺失，已停止升级，不会自动修改信任库。");
            }
            Note("UPGRADE_BASELINE_OK="+previous);
            return new(previous,installed.Nonce,installed.CertificateCreated,Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(previousPath,"Identity.msix")))));
        }
        if(Directory.Exists(legacyRoot))throw new InvalidOperationException("This test build requires a clean project baseline. Uninstall the previous build first; existing files will not be overwritten.");
        InstallPath.RequireUnused(AppRoot);
        using var arp=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\{DA975784-DC84-48EF-9A47-F60C0C969280}_is1");
        if(arp!=null)throw new InvalidOperationException("Old product uninstall entry exists.");
        if(Directory.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"SmartZip Modern")))throw new InvalidOperationException("Old product Start menu directory exists.");
        return null;
    }
    static void Inspect(string root,string? version=null,bool checkHelper=true){
        using var cert=new X509Certificate2(File.ReadAllBytes(Path.Combine(root,"Identity.cer")));
        if(cert.HasPrivateKey||cert.Subject!=ProductIdentity.Publisher||cert.Thumbprint!=ProductIdentity.CertificateThumbprint||
           Convert.ToHexString(SHA256.HashData(cert.RawData))!=ProductIdentity.CertificateSha256||
           cert.NotBefore.ToUniversalTime().Ticks!=ProductIdentity.NotBeforeTicks||cert.NotAfter.ToUniversalTime().Ticks!=ProductIdentity.NotAfterTicks||
           DateTime.UtcNow<cert.NotBefore.ToUniversalTime()||DateTime.UtcNow>cert.NotAfter.ToUniversalTime())throw new InvalidDataException("Pinned public certificate validation failed.");
        var eku=cert.Extensions.OfType<X509EnhancedKeyUsageExtension>().Single();
        if(eku.EnhancedKeyUsages.Count!=1||eku.EnhancedKeyUsages[0].Value!="1.3.6.1.5.5.7.3.3")throw new InvalidDataException("Code signing EKU required.");
        if(cert.Extensions.OfType<X509BasicConstraintsExtension>().Single().CertificateAuthority)throw new InvalidDataException("CA certificates are not allowed.");
        if(!ProductIdentity.TestSigned){
            using var chain=new X509Chain();chain.ChainPolicy.ApplicationPolicy.Add(new Oid("1.3.6.1.5.5.7.3.3"));
            if(cert.Subject==cert.Issuer||!chain.Build(cert))throw new InvalidDataException("Production signing certificate is not trusted; no automatic trust import is allowed.");
        }
        using var zip=System.IO.Compression.ZipFile.OpenRead(Path.Combine(root,"Identity.msix"));if(zip.GetEntry("AppxSignature.p7x")==null)throw new InvalidDataException("Unsigned package.");
        using var stream=zip.GetEntry("AppxManifest.xml")!.Open();var doc=XDocument.Load(stream);
        var identity=doc.Root!.Elements().Single(e=>e.Name.LocalName=="Identity");
        if((string?)identity.Attribute("Publisher")!=cert.Subject||(string?)identity.Attribute("Name")!=ProductIdentity.Name||(string?)identity.Attribute("Version")!=(version??ProductIdentity.Version))throw new InvalidDataException("Package identity mismatch.");
        var command=doc.Descendants().Single(e=>e.Name.LocalName=="Verb");
        if(!Guid.TryParse((string?)command.Attribute("Clsid"),out var guid)||guid!=Guid.Parse(Clsid))throw new InvalidDataException("Unexpected menu CLSID.");
        if(ProductIdentity.TestSigned){
        var helperFile=Path.Combine(root,"CertificateTrustHelper.exe");
        var helperHash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(helperFile)));
        if(checkHelper&&helperHash!=ProductIdentity.TrustHelperSha256)throw new InvalidDataException("Elevation binary mismatch.");
        }
    }
    static void SafeParents(string path){for(var d=new DirectoryInfo(Path.GetFullPath(path));d!=null;d=d.Parent)if(d.Exists&&(d.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Reparse-point installation paths are not allowed: "+d.FullName);}
    static void SafeTree(string path){SafeParents(path);foreach(var item in new DirectoryInfo(path).EnumerateFileSystemInfos()){if((item.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Refusing a reparse point: "+item.FullName);if(item is DirectoryInfo dir)SafeTree(dir.FullName);}}
    static void Stage(Journal j){
        SafeParents(AppRoot);
        if(j.Previous==null){InstallPath.RequireUnused(AppRoot);Directory.CreateDirectory(AppRoot);File.WriteAllText(Marker,j.Nonce);}
        InstallPath.RequireUnused(Target);Directory.CreateDirectory(Target);
        if(j.Previous!=null)File.WriteAllText(Path.Combine(Target,".install-transaction"),j.Nonce);
        SafeTree(Source);
        foreach(var file in Directory.EnumerateFiles(Source,"*",SearchOption.AllDirectories)){
            var relative=Path.GetRelativePath(Source,file);if(relative=="transaction.json")continue;
            var dest=Path.Combine(Target,relative);Directory.CreateDirectory(Path.GetDirectoryName(dest)!);File.Copy(file,dest,false);
        }
        Fault("after-stage");
    }
    static void DeleteStage(Journal j){
        var path=j.Previous==null?AppRoot:Target;var marker=j.Previous==null?Marker:Path.Combine(Target,".install-transaction");
        if(!Directory.Exists(path))return;SafeTree(path);
        if(!File.Exists(marker)||File.ReadAllText(marker)!=j.Nonce)throw new IOException("Stage ownership marker mismatch; deletion refused.");Directory.Delete(path,true);
    }
    static async Task RegisterAt(string path,bool downgrade=false){var r=await new PackageManager().AddPackageByUriAsync(new Uri(Path.Combine(path,"Identity.msix")),new AddPackageOptions{ExternalLocationUri=new Uri(path+Path.DirectorySeparatorChar),ForceUpdateFromAnyVersion=downgrade});if(r.ExtendedErrorCode!=null)throw new InvalidOperationException(r.ErrorText,r.ExtendedErrorCode);}
    static async Task Register(){await RegisterAt(Target);Fault("after-package");}
    static async Task RemovePackage(){
        var m=new PackageManager();foreach(var p in Packages(m).ToArray()){
            if(VersionOf(p)!=ProductIdentity.Version)throw new InvalidOperationException("Another version appeared; cleanup stopped.");
            var r=await m.RemovePackageAsync(p.Id.FullName);if(r.ExtendedErrorCode!=null)throw new InvalidOperationException(r.ErrorText,r.ExtendedErrorCode);
        }if(Packages(m).Any())throw new IOException("Package removal not confirmed.");
    }
    static void VerifyRegistration(string? version=null,string? path=null){
        var registered=Packages(new PackageManager()).ToArray();
        if(registered.Length!=1)throw new IOException("Expected exactly one registered package version.");
        var p=registered.SingleOrDefault(p=>VersionOf(p)==(version??ProductIdentity.Version))??throw new IOException("Expected package is not registered.");
        if(!string.Equals(p.EffectiveExternalLocation.Path.TrimEnd('\\'),path??Target,StringComparison.OrdinalIgnoreCase))throw new IOException("Package external location mismatch.");
        using var key=Registry.ClassesRoot.OpenSubKey(@"PackagedCom\Package\"+p.Id.FullName+@"\Class\"+Clsid);
        if(key==null)throw new IOException("Package exists, but packaged COM registration is missing.");
        var doc=XDocument.Load(Path.Combine(p.InstalledLocation.Path,"AppxManifest.xml"));
        if(!doc.Descendants().Any(e=>e.Name.LocalName=="Verb"&&Guid.TryParse((string?)e.Attribute("Clsid"),out var id)&&id==Guid.Parse(Clsid)))throw new IOException("Registered package has no expected context-menu declaration.");
        int init=CoInitializeEx(IntPtr.Zero,0);
        if(init<0&&init!=unchecked((int)0x80010106))Marshal.ThrowExceptionForHR(init);
        try{var clsid=Guid.Parse(Clsid);var iid=Guid.Parse("a08ce4d0-fa25-44ab-b57c-c7b1c323e0b9");
            int hr=CoCreateInstance(ref clsid,IntPtr.Zero,4,ref iid,out var command);
            if(hr<0)Marshal.ThrowExceptionForHR(hr);if(command==IntPtr.Zero)throw new IOException("COM activation returned no interface.");Marshal.Release(command);
        }finally{if(init>=0)CoUninitialize();}
    }
    static async Task Prepare(){
        var previous=Preflight();var j=new Journal(Guid.NewGuid().ToString("N"),previous?.CertificateCreated??false,WindowsIdentity.GetCurrent().User!.Value,AppRoot,previous);Save(j);
        if(previous!=null){await PrepareUpgrade(j);return;}
        var tx=new Transaction();TrustBroker? broker=null;
        try{
            await tx.Step("stage files",()=>{Stage(j);return Task.CompletedTask;},()=>{DeleteStage(j);return Task.CompletedTask;});
            if(ProductIdentity.TestSigned)
                await tx.Step("machine test trust",async()=>{broker=await TrustBroker.Open(Path.Combine(Source,"CertificateTrustHelper.exe"),true);j=j with{CertificateCreated=broker.Created};Save(j);},async()=>{if(broker!=null)await broker.Rollback();});
            await tx.Step("package",Register,RemovePackage);VerifyRegistration();
            if(broker!=null)await broker.Commit();tx.Commit();Note("PREPARED; ARP/shortcuts/product state not yet committed.");
        }catch(Exception primary){
            try{await tx.Rollback();File.Delete(Receipt);Note("ROLLBACK_COMPLETE");}
            catch(Exception cleanup){
                // If Windows refuses package removal, retain its backing trust
                // rather than disconnecting an uncommitted broker underneath it.
                if(broker!=null&&Packages(new PackageManager()).Any()){
                    try{await broker.Commit();Note("Package rollback blocked; certificate retained with package.");}
                    catch(Exception trust){Note("Certificate retention could not be confirmed: "+trust);}
                }
                if(File.Exists(Marker)&&File.ReadAllText(Marker)==j.Nonce)
                    File.WriteAllText(Path.Combine(AppRoot,"recovery.json"),JournalJson.Serialize(j));
                Note("ROLLBACK_INCOMPLETE: "+cleanup);
                throw new AggregateException(primary,cleanup);
            }throw;
        }
        finally{broker?.Dispose();}
    }
    static void Commit(){
        RequirePerUser();var j=ReadJournal();VerifyRegistration();
        var stageMarker=j.Previous==null?Marker:Path.Combine(Target,".install-transaction");
        if(File.ReadAllText(stageMarker)!=j.Nonce)throw new IOException("Transaction ownership lost.");
        Fault("before-commit");
        using var state=Registry.CurrentUser.CreateSubKey(StateKey);state.SetValue("Publisher",ProductIdentity.Publisher);state.SetValue("Version",ProductIdentity.Version);
        state.SetValue("VersionPath",Target);state.SetValue("CertificateCreated",j.CertificateCreated?1:0);state.SetValue("CertificateThumbprint",ProductIdentity.CertificateThumbprint);
        state.SetValue("UserSid",j.UserSid);
        Fault("after-state");
        File.WriteAllText(Path.Combine(Target,"installed.json"),JournalJson.Serialize(j));File.WriteAllText(Marker,j.Nonce);Note("COMMITTED");SHChangeNotify(0x08000000,0,IntPtr.Zero,IntPtr.Zero);
    }
    static void FinalizeInstall(){
        RequirePerUser();var j=ReadJournal();VerifyRegistration();
        if(File.ReadAllText(Marker)!=j.Nonce)throw new IOException("Committed marker mismatch.");
        if(j.Previous!=null)UpgradeBackup.Discard(AppRoot,j.Nonce);
        Note("FINALIZED");
    }
    static async Task RestorePreviousPackage(Journal j){
        var old=j.Previous??throw new IOException("No previous package in journal.");
        var path=Path.Combine(AppRoot,"Versions",old.Version);SafeTree(path);
        if(Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(path,"Identity.msix"))))!=old.PackageSha256)
            throw new IOException("Previous package backup was changed; rollback stopped.");
        var present=Packages(new PackageManager()).ToArray();
        if(present.Any(p=>VersionOf(p)!=old.Version&&VersionOf(p)!=ProductIdentity.Version))throw new IOException("Unexpected package appeared during rollback.");
        if(present.Length!=1||VersionOf(present[0])!=old.Version)await RegisterAt(path,true);
        VerifyRegistration(old.Version,path);
    }
    static async Task PrepareUpgrade(Journal j){
        var tx=new Transaction();
        try{
            UpgradeBackup.Capture(AppRoot,j.Nonce);
            await tx.Step("new version files",()=>{Stage(j);return Task.CompletedTask;},()=>{DeleteStage(j);return Task.CompletedTask;});
            await tx.Step("upgrade package",Register,()=>RestorePreviousPackage(j));
            VerifyRegistration();tx.Commit();Note("UPGRADE_PREPARED; previous files, configuration and certificate ownership retained.");
        }catch(Exception primary){
            try{await tx.Rollback();UpgradeBackup.Discard(AppRoot,j.Nonce);File.Delete(Receipt);Note("UPGRADE_ROLLBACK_COMPLETE");}
            catch(Exception cleanup){Note("UPGRADE_ROLLBACK_INCOMPLETE="+cleanup);throw new AggregateException(primary,cleanup);}
            throw;
        }
    }
    static async Task RollbackPrepared(){
        RequirePerUser();if(!File.Exists(Receipt))return;var j=ReadJournal();
        if(j.Previous!=null){
            await RestorePreviousPackage(j);UpgradeBackup.Restore(AppRoot,j.Nonce);DeleteStage(j);UpgradeBackup.Discard(AppRoot,j.Nonce);File.Delete(Receipt);
            Note("UPGRADE_ROLLBACK_COMPLETE; original package, registry, uninstaller and shortcuts restored.");return;
        }
        await RemovePackage();if(ProductIdentity.TestSigned){using var b=await TrustBroker.Open(Path.Combine(Source,"CertificateTrustHelper.exe"),false);await b.Release(j.CertificateCreated);}
        Registry.CurrentUser.DeleteSubKeyTree(StateKey,false);DeleteStage(j);File.Delete(Receipt);Note("ROLLBACK_COMPLETE");
    }
    static async Task Uninstall(){
        RequirePerUser();if(!string.Equals(Source,Target,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Unexpected uninstall helper location.");
        using var state=Registry.CurrentUser.OpenSubKey(StateKey);
        if(state==null||!string.Equals(state.GetValue("VersionPath") as string,Target,StringComparison.OrdinalIgnoreCase)||(state.GetValue("Publisher") as string)!=ProductIdentity.Publisher||(state.GetValue("CertificateThumbprint") as string)!=ProductIdentity.CertificateThumbprint||(state.GetValue("UserSid") as string)!=WindowsIdentity.GetCurrent().User?.Value)throw new InvalidDataException("Product state identity mismatch.");
        bool created=Convert.ToInt32(state.GetValue("CertificateCreated",0))==1;
        // Cancelled UAC leaves the registered install intact.
        using var broker=ProductIdentity.TestSigned?await TrustBroker.Open(Path.Combine(Source,"CertificateTrustHelper.exe"),false):null;
        await RemovePackage();if(broker!=null)Note("Certificate cleanup: "+await broker.Release(created));
        state.Dispose();Registry.CurrentUser.DeleteSubKeyTree(StateKey,false);SHChangeNotify(0x08000000,0,IntPtr.Zero,IntPtr.Zero);
    }
}
