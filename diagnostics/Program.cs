using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;
using Windows.Management.Deployment;

// Diagnostic-only executable: local logs are its only persistent writes.
internal static class Program {
    const string StateKey = @"Software\SmartZipModern";
    const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\{DA975784-DC84-48EF-9A47-F60C0C969280}_is1";
    const string PackageName = "SmartZip.Modern";
    const string Publisher = "CN=SmartZip Modern Evaluation";
    static readonly string Source = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
    static readonly string Root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "SmartZip Modern");
    static readonly string LogPath = Path.Combine(Path.GetTempPath(), "SmartZip-Preflight-Diagnostic-" + Environment.ProcessId + ".log");
    static void Log(string key, object? value) => File.AppendAllText(LogPath,
        $"{DateTimeOffset.Now:O} {key}={Convert.ToString(value)?.Replace("\r", "\\r").Replace("\n", "\\n")}\n", Encoding.UTF8);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int MessageBoxW(IntPtr h,string text,string caption,uint type);
    [DllImport("ntdll.dll")] static extern int NtQueryKey(SafeRegistryHandle key,int info,byte[] buffer,int size,out int resultSize);
    [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr process,int info,byte[] buffer,int size,out int resultSize);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern int GetCurrentPackageFullName(ref uint length,StringBuilder name);

    static string NativeKey(RegistryKey key) {
        var buffer=new byte[8192];
        int status=NtQueryKey(key.Handle,3,buffer,buffer.Length,out _);
        if(status!=0)return "NtQueryKey status 0x"+status.ToString("X8");
        int length=BitConverter.ToInt32(buffer,0);
        return length>=0 && length<=buffer.Length-4 ? Encoding.Unicode.GetString(buffer,4,length) : "Invalid key-name length";
    }
    static void Probe(string name, Action read) {
        try { read(); } catch(Exception e) { Log(name+".ERROR",e.GetType().Name+" 0x"+e.HResult.ToString("X8")+" "+e.Message); }
    }
    static void Identity() {
        Log("DIAGNOSTIC_ONLY","No deployment or certificate-writing code is linked. Only logs and temporary extraction are written.");
        Log("ProbeVersion","1");
        Log("ProcessId",Environment.ProcessId);
        Log("Is64BitProcess",Environment.Is64BitProcess);
        Log("OS",Environment.OSVersion);
        Log("Source",Source);
        Log("ProcessPath",Environment.ProcessPath);
        Log("CurrentDirectory",Environment.CurrentDirectory);
        Log("UserSID",WindowsIdentity.GetCurrent().User?.Value);
        Log("GetFolderPath.LocalApplicationData",Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
        foreach(string variable in new[]{"LOCALAPPDATA","APPDATA","USERPROFILE","TEMP","TMP","__COMPAT_LAYER","DOTNET_BUNDLE_EXTRACT_BASE_DIR","DOTNET_ROOT","DOTNET_STARTUP_HOOKS"})
            Log("Environment."+variable,Environment.GetEnvironmentVariable(variable));
        Log("TEST8.AppRoot",Root);
        Probe("SelfHash",()=>Log("SelfSHA256",Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Environment.ProcessPath!)))));
        Probe("Parent",()=>{
            var basic=new byte[IntPtr.Size*6];
            int status=NtQueryInformationProcess(Process.GetCurrentProcess().Handle,0,basic,basic.Length,out _);
            Log("ProcessBasicInfoStatus",status);
            if(status==0){
                long id=IntPtr.Size==8?BitConverter.ToInt64(basic,IntPtr.Size*5):BitConverter.ToInt32(basic,IntPtr.Size*5);
                using var parent=Process.GetProcessById(checked((int)id));
                Log("ParentPID",id); Log("ParentName",parent.ProcessName); Log("ParentPath",parent.MainModule?.FileName);
            }
        });
        Probe("CurrentPackageIdentity",()=>{
            uint size=2048;var name=new StringBuilder((int)size);
            int result=GetCurrentPackageFullName(ref size,name);
            Log("CurrentPackageIdentityStatus",result);Log("CurrentPackageIdentity",result==0?name.ToString():"none/error");
        });
        Probe("TEST8.UserContext",()=>UserContext.Require(line=>Log("TEST8.UserContext",line)));
    }
    static bool WouldBlock(bool directory, bool key, bool package) => directory || key || package;
    static void Test8Snapshot(int index) {
        Log("SNAPSHOT",index);
        // Match test8's order: open HKCU key, check Directory.Exists, check key, enumerate packages.
        // Unlike short-circuiting test8, evaluate all three so the log identifies each cause.
        using var key=Registry.CurrentUser.OpenSubKey(StateKey);
        bool directory=Directory.Exists(Root), hasKey=key!=null;
        Log("TEST8.DirectoryExists",directory); Log("TEST8.ProductStateKeyExists",hasKey);
        // HKCU's predefined pseudo-handle is not accepted by NtQueryKey; open a real handle.
        using var currentUser=RegistryKey.OpenBaseKey(RegistryHive.CurrentUser,RegistryView.Registry64);
        Log("TEST8.HKCURootNativeName",NativeKey(currentUser));
        if(key!=null){
            Log("TEST8.ProductStateNativeName",NativeKey(key));
            foreach(string name in new[]{"Version","VersionPath","Publisher","UserSid","CertificateCreated"})
                Log("TEST8.ProductState."+name,key.GetValue(name));
        }
        var manager=new PackageManager();
        var matches=manager.FindPackagesForUser("").Where(p=>p.Id.Name==PackageName&&p.Id.Publisher==Publisher).ToArray();
        Log("TEST8.FindPackagesForUserEmpty.MatchCount",matches.Length);
        foreach(var package in matches){
            Log("TEST8.Package.FullName",package.Id.FullName);
            Log("TEST8.Package.Publisher",package.Id.Publisher);
            Probe("PackageLocation",()=>Log("TEST8.Package.InstalledLocation",package.InstalledLocation.Path));
            Probe("PackageStatus",()=>Log("TEST8.Package.StatusOK",package.Status.VerifyIsOK()));
        }
        bool block=WouldBlock(directory,hasKey,matches.Length!=0);
        Log("TEST8.WOULD_THROW_EXISTING_INSTALL",block);
        Log("TEST8.Trigger",string.Join(",",new[]{directory?"DIRECTORY":null,hasKey?"PRODUCT_KEY":null,matches.Length!=0?"PACKAGE":null}.Where(x=>x!=null)));
    }
    static void Supplement() {
        Probe("ExplicitSIDPackages",()=>{
            var manager=new PackageManager();
            var packages=manager.FindPackagesForUser(WindowsIdentity.GetCurrent().User!.Value)
                .Where(p=>p.Id.Name==PackageName&&p.Id.Publisher==Publisher).Select(p=>p.Id.FullName).ToArray();
            Log("ExplicitSIDPackages.Count",packages.Length);
            foreach(var name in packages)Log("ExplicitSIDPackages.FullName",name);
        });
        foreach(var view in new[]{RegistryView.Registry64,RegistryView.Registry32})Probe("Registry."+view,()=>{
            using var hive=RegistryKey.OpenBaseKey(RegistryHive.CurrentUser,view);
            Log("Registry."+view+".HKCU",NativeKey(hive));
            using var key=hive.OpenSubKey(StateKey);using var uninstall=hive.OpenSubKey(UninstallKey);
            Log("Registry."+view+".ProductKeyExists",key!=null);
            if(key!=null)Log("Registry."+view+".ProductKeyNativeName",NativeKey(key));
            Log("Registry."+view+".UninstallExists",uninstall!=null);
        });
        Probe("DirectoryAttributes",()=>{
            try{Log("Root.FileAttributes",File.GetAttributes(Root));}
            catch(Exception e){Log("Root.FileAttributesError",e.GetType().Name+" 0x"+e.HResult.ToString("X8"));}
            if(Directory.Exists(Root))foreach(var entry in new DirectoryInfo(Root).EnumerateFileSystemInfos().Take(32))
                Log("Root.Child",entry.Name+" | "+entry.Attributes+" | created="+entry.CreationTimeUtc.ToString("O"));
        });
    }
    static async Task<int> Main(string[] args) {
        if(args.Length<1 || args.Length>2 || (args[0]!="preflight"&&args[0]!="self-test") || (args.Length==2&&args[1]!="--no-ui"))return 2;
        if(args[0]=="self-test"){
            for(int i=0;i<8;i++)if(WouldBlock((i&1)!=0,(i&2)!=0,(i&4)!=0)!=(i!=0))return 3;
            return 0;
        }
        int exit=0;
        try{
            Identity();
            for(int i=1;i<=3;i++){
                try{Test8Snapshot(i);}catch(Exception e){exit=1;Log("SNAPSHOT.ERROR",e.ToString());}
                if(i<3)await Task.Delay(200);
            }
            Supplement();
            Log("DIAGNOSTIC_COMPLETE","Intentional stop; no install attempted.");
        }catch(Exception e){exit=1;Log("FATAL",e.ToString());}
        if(!args.Contains("--no-ui"))MessageBoxW(IntPtr.Zero,
            "诊断采集已结束。这不是安装失败：此程序只检查，不会安装软件、注册 Package 或导入证书。\n\n请把下方日志文件路径或此窗口截图发给开发者：\n"+LogPath,
            "SmartZip 只读诊断",0x40);
        return exit;
    }
}
