using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32;
using Windows.Management.Deployment;

internal static class Program {
    static readonly string Root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","SmartZip Modern");
    static readonly string LogPath=Path.Combine(Path.GetTempPath(),"SmartZip-Repair-test8-"+Environment.ProcessId+".log");
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int MessageBoxW(IntPtr h,string text,string title,uint flags);
    static void Log(string value)=>File.AppendAllText(LogPath,DateTimeOffset.Now.ToString("O")+" "+value+Environment.NewLine,Encoding.UTF8);
    static void RequireAbsent(string path) {
        // Directory.Exists suppresses access errors. Only genuine path-not-found counts as absent.
        try { _=File.GetAttributes(path); }
        catch(FileNotFoundException){return;}
        catch(DirectoryNotFoundException){return;}
        throw new IOException("程序目录仍存在或不可确认，已停止："+path);
    }
    static void RequireOrphan(string sid) {
        RequireAbsent(Root);
        RequireAbsent(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","SmartZip"));
        var manager=new PackageManager();
        foreach(var user in new[]{"",sid})
            if(manager.FindPackagesForUser(user).Any(p=>p.Id.Name=="SmartZip.Modern"))
                throw new IOException("当前用户仍注册了 SmartZip Package，不能清理状态键。");
        foreach(var process in Process.GetProcesses())using(process){
            if(process.ProcessName.StartsWith("SmartZipModernSetup",StringComparison.OrdinalIgnoreCase)||
               process.ProcessName.StartsWith("SmartZipSetup",StringComparison.OrdinalIgnoreCase)||
               process.ProcessName.StartsWith("SmartZip-Preflight-Diagnostic",StringComparison.OrdinalIgnoreCase)||
               process.ProcessName=="DeploymentHelper")
                throw new IOException("请先关闭 SmartZip 安装器和只读诊断窗口，再运行修复工具。");
        }
    }
    static SavedKey[] ReadAll(RegistryKey hive) => RepairPolicy.Keys.Select(p=>Snapshot.Read(hive,p)).Where(k=>k!=null).Cast<SavedKey>().ToArray();
    static void AssertUnchanged(RegistryKey hive,SavedKey[] expected) {
        if(Snapshot.Json(ReadAll(hive))!=Snapshot.Json(expected))throw new IOException("注册表状态已变化，停止操作。请重新检查。");
    }
    static void SafeParents(string path) {
        for(var d=new DirectoryInfo(path);d!=null;d=d.Parent)
            if(d.Exists&&(d.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("备份路径包含目录联接或符号链接，已停止。");
    }
    static string Backup(SavedKey[] keys) {
        var directory=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"SmartZip","RepairBackups",DateTime.UtcNow.ToString("yyyyMMdd-HHmmss")+"-"+Guid.NewGuid().ToString("N"));
        SafeParents(directory);
        string reg=Snapshot.RegFile(keys),json=Snapshot.Json(keys);
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory,"test8-registry.reg"),reg,Encoding.Unicode);
        File.WriteAllText(Path.Combine(directory,"snapshot.json"),json,Encoding.UTF8);
        if(File.ReadAllText(Path.Combine(directory,"test8-registry.reg"),Encoding.Unicode)!=reg||File.ReadAllText(Path.Combine(directory,"snapshot.json"))!=json)
            throw new IOException("备份校验失败，未执行删除。");
        Log("BACKUP="+directory);
        Log("BACKUP_SHA256="+Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(directory,"test8-registry.reg")))));
        return directory;
    }
    static void DeleteExact(RegistryKey hive,string path) {
        RepairPolicy.RequireAllowedKey(path);
        // Non-recursive deletion deliberately fails if unexpected subkeys appear.
        hive.DeleteSubKey(path,true);
    }
    static void RestoreMissing(RegistryKey hive,SavedKey[] keys) {
        foreach(var saved in keys){
            RepairPolicy.RequireAllowedKey(saved.Path);
            var now=Snapshot.Read(hive,saved.Path);
            if(now!=null){if(!Snapshot.Same(now,saved))throw new IOException("回滚遇到外部修改，保留备份并停止。");continue;}
            using var key=hive.CreateSubKey(saved.Path);
            foreach(var value in saved.Values)key.SetValue(value.Name,value.Value(),value.Kind);
            key.Flush();
        }
        AssertUnchanged(hive,keys);
        Log("ROLLBACK_RESTORED");
    }
    static int Main(string[] args) {
        if(args.SequenceEqual(new[]{"--self-test"})){SelfTests.Run();return 0;}
        bool inspect=args.SequenceEqual(new[]{"--inspect"});
        if(args.Length!=0&&!inspect)return 2;
        try{
            string sid=UserContext.Require(Log);
            RequireOrphan(sid);
            using var hive=RegistryKey.OpenBaseKey(RegistryHive.CurrentUser,RegistryView.Registry64);
            var keys=ReadAll(hive);
            Log("VISIBLE_KEYS="+string.Join(",",keys.Select(k=>k.Path)));
            Log("PROJECT_SNAPSHOT="+Snapshot.Json(keys));
            if(keys.Length==0){
                Log("NO_VISIBLE_RESIDUE_NO_CHANGE");
                if(!inspect)MessageBoxW(IntPtr.Zero,"当前启动环境没有发现目标残留，未修改任何内容。\n这不代表其他启动环境也没有残留。请从资源管理器双击此工具。\n\n日志："+LogPath,"SmartZip 修复检查",0x40);
                return 10;
            }
            RepairPolicy.Validate(keys,Root,sid);
            using(var alternate=RegistryKey.OpenBaseKey(RegistryHive.CurrentUser,RegistryView.Registry32))
                if(Snapshot.Json(ReadAll(alternate))!=Snapshot.Json(keys))throw new IOException("32/64 位视图不一致，已停止清理。");
            if(inspect){Log("INSPECT_VALIDATED_NO_CHANGE");return 0;}
            if(MessageBoxW(IntPtr.Zero,"已确认 test8 程序目录和 Package 均不存在。\n\n将先备份，再删除当前用户中的两个项目专用状态/卸载注册表项。不会删除文件、证书或其他软件信息。\n\n是否开始修复？", "SmartZip test8 残留修复",0x124)!=6){Log("USER_CANCELLED_NO_CHANGE");return 0;}
            RequireOrphan(sid);AssertUnchanged(hive,keys);
            string backup=Backup(keys);
            RequireOrphan(sid);AssertUnchanged(hive,keys);
            try {
                foreach(var saved in keys){
                    if(!Snapshot.Same(Snapshot.Read(hive,saved.Path),saved))throw new IOException("删除前状态已变化。");
                    DeleteExact(hive,saved.Path);Log("REMOVED="+saved.Path);
                }
                if(ReadAll(hive).Length!=0)throw new IOException("清理后仍检测到残留。");
                using var alternate=RegistryKey.OpenBaseKey(RegistryHive.CurrentUser,RegistryView.Registry32);
                if(ReadAll(alternate).Length!=0)throw new IOException("另一注册表视图中仍有残留。");
                Log("REPAIR_SUCCESS_SAME_PROCESS_VERIFIED");
            }catch(Exception primary){
                Log("CLEANUP_FAILED="+primary);
                try{RestoreMissing(hive,keys);}catch(Exception restore){Log("ROLLBACK_INCOMPLETE="+restore);throw new AggregateException("修复未完成且回滚不完整，请保留日志和备份。",primary,restore);}
                throw;
            }
            MessageBoxW(IntPtr.Zero,"项目注册表残留已清理，并已在同一启动环境复查。\n\n备份："+backup+"\n\n日志："+LogPath+"\n\n请关闭本窗口，将结果告诉开发者；本工具不会自动安装软件。","SmartZip 修复完成",0x40);
            return 0;
        }catch(Exception e){
            Log("ERROR="+e);
            if(!inspect)MessageBoxW(IntPtr.Zero,"修复未完成。\n"+e.Message+"\n\n请保留日志：\n"+LogPath,"SmartZip 修复已停止",0x10);
            return 1;
        }
    }
}
