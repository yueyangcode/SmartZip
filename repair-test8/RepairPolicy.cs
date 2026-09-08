internal static class RepairPolicy {
    internal const string StateKey=@"Software\SmartZipModern";
    internal const string UninstallKey=@"Software\Microsoft\Windows\CurrentVersion\Uninstall\{DA975784-DC84-48EF-9A47-F60C0C969280}_is1";
    internal const string Publisher="CN=SmartZip Modern Evaluation";
    internal const string Version="0.1.0.7";
    internal static readonly string[] Keys={StateKey,UninstallKey};
    internal static void RequireAllowedKey(string path) {
        if(!Keys.Contains(path,StringComparer.Ordinal))throw new IOException("拒绝操作非本项目注册表键。");
    }
    internal static void Validate(SavedKey[] keys,string root,string sid) {
        foreach(var key in keys){
            RequireAllowedKey(key.Path);
            if(key.Path==StateKey){
                if(key.Text("Publisher")!=Publisher||key.Text("Version")!=Version||key.Text("UserSid")!=sid||
                   !string.Equals(key.Text("VersionPath"),Path.Combine(root,"Versions",Version),StringComparison.OrdinalIgnoreCase)||
                   key.Text("CertificateThumbprint")!="A1709CED9DB02150E2FB40CE6496BD1938D89195")
                    throw new IOException("产品身份或版本不符；工具只修复 test8（0.1.0.7）残留。");
            }else{
                var name=key.Text("DisplayName")??"";
                if(!(name=="SmartZip Modern"||name.StartsWith("SmartZip Modern ",StringComparison.Ordinal))||
                   key.Text("DisplayVersion")!=Version||
                   !string.Equals(key.Text("InstallLocation")?.TrimEnd('\\'),root,StringComparison.OrdinalIgnoreCase)||
                   !string.Equals(key.Text("UninstallString"),"\""+Path.Combine(root,"unins000.exe")+"\"",StringComparison.OrdinalIgnoreCase))
                    throw new IOException("卸载项的名称、版本或路径不符，已停止清理。");
            }
        }
    }
}
