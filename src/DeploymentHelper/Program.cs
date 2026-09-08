using Microsoft.Win32;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Xml.Linq;
using Windows.Management.Deployment;

internal static class Program {
    const string StateKey=@"Software\SmartZipModern";
    const string Clsid="{C12835D9-8B49-48D9-AE52-5E66D31209E1}";
    static readonly string Source=AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
    static readonly string AppRoot=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","SmartZip Modern");
    static readonly string Target=Path.Combine(AppRoot,"Versions",ProductIdentity.Version);
    static readonly string Receipt=Path.Combine(Source,"transaction.json");
    static readonly string Log=Path.Combine(Path.GetTempPath(),"SmartZipModern-test6-"+Environment.ProcessId+".log");
    static void Note(string message)=>File.AppendAllText(Log,DateTimeOffset.Now+" "+message+Environment.NewLine,Encoding.UTF8);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int MessageBoxW(IntPtr h,string text,string caption,uint type);
    [DllImport("shell32.dll")] static extern void SHChangeNotify(uint e,uint f,IntPtr a,IntPtr b);
    [DllImport("ole32.dll")] static extern int CoInitializeEx(IntPtr p,uint flags);
    [DllImport("ole32.dll")] static extern void CoUninitialize();
    [DllImport("ole32.dll")] static extern int CoCreateInstance(ref Guid clsid,IntPtr outer,uint context,ref Guid iid,out IntPtr value);
    sealed record Journal(string Nonce,bool CertificateCreated,string UserSid);
    static string Marker=>Path.Combine(AppRoot,".install-transaction");
    static void Save(Journal j)=>File.WriteAllText(Receipt,JsonSerializer.Serialize(j));
    static Journal ReadJournal(){
        var j=JsonSerializer.Deserialize<Journal>(File.ReadAllText(Receipt))??throw new InvalidDataException("Missing transaction receipt.");
        if(j.UserSid!=WindowsIdentity.GetCurrent().User?.Value)throw new InvalidDataException("Transaction user identity mismatch.");
        return j;
    }
    static IEnumerable<Windows.ApplicationModel.Package> Packages(PackageManager m)=>m.FindPackagesForUser("").Where(p=>p.Id.Name==ProductIdentity.Name&&p.Id.Publisher==ProductIdentity.Publisher);
    static string VersionOf(Windows.ApplicationModel.Package p)=>$"{p.Id.Version.Major}.{p.Id.Version.Minor}.{p.Id.Version.Build}.{p.Id.Version.Revision}";

    static async Task<int> Main(string[] args){
        try{
            if(args.Length<1||args.Length>2||(args.Length==2&&args[1]!="--no-ui"))throw new ArgumentException("Only a fixed operation and optional --no-ui are accepted.");
            switch(args[0]){
                case "inspect":Inspect(Source);break;
                case "preflight":Preflight();break;
                case "prepare":await Prepare();break;
                case "commit":Commit();break;
                case "rollback":await RollbackPrepared();break;
                case "uninstall":await Uninstall();break;
                default:throw new ArgumentException("Unknown operation.");
            }return 0;
        }catch(Exception ex){Note(ex.ToString());if(!args.Contains("--no-ui"))MessageBoxW(IntPtr.Zero,ex.Message+"\n\nLog: "+Log,"SmartZip Modern test6",0x10);return 1;}
    }
    static void RequirePerUser(){
        UserContext.Require(Note);
    }
    static void Preflight(){
        RequirePerUser();if(RuntimeInformation.OSArchitecture!=Architecture.X64||!OperatingSystem.IsWindowsVersionAtLeast(10,0,22621))throw new InvalidOperationException("Windows 11 x64 required.");
        // ponytail: test builds cover clean installation. Block upgrades rather than
        // overwrite a working install before upgrade rollback is implemented.
        using var key=Registry.CurrentUser.OpenSubKey(StateKey);
        if(Directory.Exists(AppRoot)||key!=null||Packages(new PackageManager()).Any())throw new InvalidOperationException("This test build requires a clean project baseline. Uninstall the previous build first; existing files will not be overwritten.");
        using var arp=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\{DA975784-DC84-48EF-9A47-F60C0C969280}_is1");
        if(arp!=null)throw new InvalidOperationException("Old product uninstall entry exists.");
        if(Directory.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"SmartZip Modern")))throw new InvalidOperationException("Old product Start menu directory exists.");
        SafeParents(AppRoot);Inspect(Source);
    }
    static void Inspect(string root){
        using var cert=new X509Certificate2(File.ReadAllBytes(Path.Combine(root,"Identity.cer")));
        if(cert.HasPrivateKey||cert.Subject!=ProductIdentity.Publisher||cert.Thumbprint!=ProductIdentity.CertificateThumbprint||
           Convert.ToHexString(SHA256.HashData(cert.RawData))!=ProductIdentity.CertificateSha256||
           cert.NotBefore.ToUniversalTime().Ticks!=ProductIdentity.NotBeforeTicks||cert.NotAfter.ToUniversalTime().Ticks!=ProductIdentity.NotAfterTicks||
           DateTime.UtcNow<cert.NotBefore.ToUniversalTime()||DateTime.UtcNow>cert.NotAfter.ToUniversalTime())throw new InvalidDataException("Pinned public certificate validation failed.");
        var eku=cert.Extensions.OfType<X509EnhancedKeyUsageExtension>().Single();
        if(eku.EnhancedKeyUsages.Count!=1||eku.EnhancedKeyUsages[0].Value!="1.3.6.1.5.5.7.3.3")throw new InvalidDataException("Code signing EKU required.");
        if(cert.Extensions.OfType<X509BasicConstraintsExtension>().Single().CertificateAuthority)throw new InvalidDataException("CA certificates are not allowed.");
        using var zip=System.IO.Compression.ZipFile.OpenRead(Path.Combine(root,"Identity.msix"));if(zip.GetEntry("AppxSignature.p7x")==null)throw new InvalidDataException("Unsigned package.");
        using var stream=zip.GetEntry("AppxManifest.xml")!.Open();var doc=XDocument.Load(stream);
        var identity=doc.Root!.Elements().Single(e=>e.Name.LocalName=="Identity");
        if((string?)identity.Attribute("Publisher")!=cert.Subject||(string?)identity.Attribute("Name")!=ProductIdentity.Name||(string?)identity.Attribute("Version")!=ProductIdentity.Version)throw new InvalidDataException("Package identity mismatch.");
        var command=doc.Descendants().Single(e=>e.Name.LocalName=="Verb");
        if(!Guid.TryParse((string?)command.Attribute("Clsid"),out var guid)||guid!=Guid.Parse(Clsid))throw new InvalidDataException("Unexpected menu CLSID.");
        var helperFile=Path.Combine(root,"CertificateTrustHelper.exe");
        var helperHash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(helperFile)));
        if(helperHash!=ProductIdentity.TrustHelperSha256)throw new InvalidDataException("Elevation binary mismatch.");
    }
    static void SafeParents(string path){for(var d=new DirectoryInfo(Path.GetFullPath(path));d!=null;d=d.Parent)if(d.Exists&&(d.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Reparse-point installation paths are not allowed: "+d.FullName);}
    static void SafeTree(string path){SafeParents(path);foreach(var item in new DirectoryInfo(path).EnumerateFileSystemInfos()){if((item.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Refusing a reparse point: "+item.FullName);if(item is DirectoryInfo dir)SafeTree(dir.FullName);}}
    static void Stage(Journal j){
        if(Directory.Exists(AppRoot))throw new IOException("Target appeared after preflight.");Directory.CreateDirectory(AppRoot);
        File.WriteAllText(Marker,j.Nonce);Directory.CreateDirectory(Target);SafeTree(Source);
        foreach(var file in Directory.EnumerateFiles(Source,"*",SearchOption.AllDirectories)){
            var relative=Path.GetRelativePath(Source,file);if(relative=="transaction.json")continue;
            var dest=Path.Combine(Target,relative);Directory.CreateDirectory(Path.GetDirectoryName(dest)!);File.Copy(file,dest,false);
        }
    }
    static void DeleteStage(Journal j){
        if(!Directory.Exists(AppRoot))return;SafeTree(AppRoot);
        if(!File.Exists(Marker)||File.ReadAllText(Marker)!=j.Nonce)throw new IOException("Stage ownership marker mismatch; deletion refused.");Directory.Delete(AppRoot,true);
    }
    static async Task Register(){var r=await new PackageManager().AddPackageByUriAsync(new Uri(Path.Combine(Target,"Identity.msix")),new AddPackageOptions{ExternalLocationUri=new Uri(Target+Path.DirectorySeparatorChar)});if(r.ExtendedErrorCode!=null)throw new InvalidOperationException(r.ErrorText,r.ExtendedErrorCode);}
    static async Task RemovePackage(){
        var m=new PackageManager();foreach(var p in Packages(m).ToArray()){
            if(VersionOf(p)!=ProductIdentity.Version)throw new InvalidOperationException("Another version appeared; cleanup stopped.");
            var r=await m.RemovePackageAsync(p.Id.FullName);if(r.ExtendedErrorCode!=null)throw new InvalidOperationException(r.ErrorText,r.ExtendedErrorCode);
        }if(Packages(m).Any())throw new IOException("Package removal not confirmed.");
    }
    static void VerifyRegistration(){
        var p=Packages(new PackageManager()).SingleOrDefault(p=>VersionOf(p)==ProductIdentity.Version)??throw new IOException("Expected package is not registered.");
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
        Preflight();var j=new Journal(Guid.NewGuid().ToString("N"),false,WindowsIdentity.GetCurrent().User!.Value);Save(j);var tx=new Transaction();TrustBroker? broker=null;
        try{
            await tx.Step("stage files",()=>{Stage(j);return Task.CompletedTask;},()=>{DeleteStage(j);return Task.CompletedTask;});
            await tx.Step("machine test trust",async()=>{broker=await TrustBroker.Open(Path.Combine(Source,"CertificateTrustHelper.exe"),true);j=j with{CertificateCreated=broker.Created};Save(j);},async()=>{if(broker!=null)await broker.Rollback();});
            await tx.Step("package",Register,RemovePackage);VerifyRegistration();
            await broker!.Commit();tx.Commit();Note("PREPARED; ARP/shortcuts/product state not yet committed.");
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
                    File.WriteAllText(Path.Combine(AppRoot,"recovery.json"),JsonSerializer.Serialize(j));
                Note("ROLLBACK_INCOMPLETE: "+cleanup);
                throw new AggregateException(primary,cleanup);
            }throw;
        }
        finally{broker?.Dispose();}
    }
    static void Commit(){
        RequirePerUser();var j=ReadJournal();VerifyRegistration();if(File.ReadAllText(Marker)!=j.Nonce)throw new IOException("Transaction ownership lost.");
        using var state=Registry.CurrentUser.CreateSubKey(StateKey);state.SetValue("Publisher",ProductIdentity.Publisher);state.SetValue("Version",ProductIdentity.Version);
        state.SetValue("VersionPath",Target);state.SetValue("CertificateCreated",j.CertificateCreated?1:0);state.SetValue("CertificateThumbprint",ProductIdentity.CertificateThumbprint);
        state.SetValue("UserSid",j.UserSid);
        File.WriteAllText(Path.Combine(Target,"installed.json"),JsonSerializer.Serialize(j));Note("COMMITTED");SHChangeNotify(0x08000000,0,IntPtr.Zero,IntPtr.Zero);
    }
    static async Task RollbackPrepared(){
        RequirePerUser();if(!File.Exists(Receipt))return;var j=ReadJournal();
        await RemovePackage();using(var b=await TrustBroker.Open(Path.Combine(Source,"CertificateTrustHelper.exe"),false)){await b.Release(j.CertificateCreated);}
        Registry.CurrentUser.DeleteSubKeyTree(StateKey,false);DeleteStage(j);File.Delete(Receipt);Note("ROLLBACK_COMPLETE");
    }
    static async Task Uninstall(){
        RequirePerUser();if(!string.Equals(Source,Target,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Unexpected uninstall helper location.");
        using var state=Registry.CurrentUser.OpenSubKey(StateKey);
        if(state==null||(state.GetValue("Publisher") as string)!=ProductIdentity.Publisher||(state.GetValue("CertificateThumbprint") as string)!=ProductIdentity.CertificateThumbprint||(state.GetValue("UserSid") as string)!=WindowsIdentity.GetCurrent().User?.Value)throw new InvalidDataException("Product state identity mismatch.");
        bool created=Convert.ToInt32(state.GetValue("CertificateCreated",0))==1;
        // Cancelled UAC leaves the registered install intact.
        using var broker=await TrustBroker.Open(Path.Combine(Source,"CertificateTrustHelper.exe"),false);
        await RemovePackage();Note("Certificate cleanup: "+await broker.Release(created));
        state.Dispose();Registry.CurrentUser.DeleteSubKeyTree(StateKey,false);SHChangeNotify(0x08000000,0,IntPtr.Zero,IntPtr.Zero);
    }
}
