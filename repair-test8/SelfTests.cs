using Microsoft.Win32;
using System.Text.Json;

internal static class SelfTests {
    static void Check(bool value) { if(!value)throw new Exception("Repair safety self-test failed."); }
    static void Reject(Action action) {
        try{action();}catch(IOException){return;}
        throw new Exception("Unsafe input was not rejected.");
    }
    internal static void Run() {
        // Pure in-memory tests: never open or modify the real registry.
        const string root=@"C:\Users\测试\AppData\Local\Programs\SmartZip Modern";
        const string sid="S-1-5-21-1-2-3-1001";
        SavedValue Text(string name,string value)=>new(name,RegistryValueKind.String,new[]{value});
        var state=new SavedKey(RepairPolicy.StateKey,new[]{
            Text("Publisher",RepairPolicy.Publisher),Text("Version",RepairPolicy.Version),Text("UserSid",sid),
            Text("VersionPath",Path.Combine(root,"Versions",RepairPolicy.Version)),
            Text("CertificateThumbprint","A1709CED9DB02150E2FB40CE6496BD1938D89195")});
        var uninstall=new SavedKey(RepairPolicy.UninstallKey,new[]{
            Text("DisplayName","SmartZip Modern 0.1.0.7 (本机开发测试版)"),Text("DisplayVersion",RepairPolicy.Version),
            Text("InstallLocation",root+"\\"),Text("UninstallString","\""+Path.Combine(root,"unins000.exe")+"\"")});
        var keys=new[]{state,uninstall};
        RepairPolicy.Validate(keys,root,sid);
        RepairPolicy.Validate(new[]{state},root,sid);
        RepairPolicy.Validate(new[]{uninstall},root,sid);
        foreach(var key in keys)foreach(var value in key.Values){
            var invalid=key with {Values=key.Values.Select(v=>v.Name==value.Name?Text(v.Name,"invalid"):v).ToArray()};
            Reject(()=>RepairPolicy.Validate(new[]{invalid},root,sid));
        }
        Reject(()=>RepairPolicy.Validate(new[]{state with {Path=@"Software\OtherSoftware"}},root,sid));
        Reject(()=>RepairPolicy.RequireAllowedKey(RepairPolicy.StateKey+@"\Child"));
        Reject(()=>RepairPolicy.RequireAllowedKey("Software"));
        var all=new SavedKey(RepairPolicy.StateKey,new SavedValue[]{
            Text("","中文\r\n值"),Text("a\"b\\c","quoted"),
            new("Expand",RegistryValueKind.ExpandString,new[]{"%LOCALAPPDATA%"}),
            new("Multi",RegistryValueKind.MultiString,new[]{"第一","second"}),
            new("Dword",RegistryValueKind.DWord,new[]{"-1"}),
            new("Qword",RegistryValueKind.QWord,new[]{"-2"}),
            new("Binary",RegistryValueKind.Binary,new[]{Convert.ToBase64String(new byte[]{0,1,255})})});
        var json=Snapshot.Json(new[]{all});
        var restored=JsonSerializer.Deserialize(json,BackupJson.Default.SavedKeyArray)!;
        Check(Snapshot.Same(restored.Single(),all));
        Check(Snapshot.Same(null,null)&&!Snapshot.Same(null,all));
        Check(!Snapshot.Same(state,state with {Values=Array.Empty<SavedValue>()}));
        Check((int)restored[0].Values[4].Value()==-1);
        Check((long)restored[0].Values[5].Value()==-2);
        Check(((byte[])restored[0].Values[6].Value()).SequenceEqual(new byte[]{0,1,255}));
        Check(((string[])restored[0].Values[3].Value()).SequenceEqual(new[]{"第一","second"}));
        var reg=Snapshot.RegFile(new[]{all});
        Check(reg.StartsWith("Windows Registry Editor Version 5.00\r\n\r\n[HKEY_CURRENT_USER\\Software\\SmartZipModern]\r\n"));
        Check(reg.Contains("@=hex(1):2d,4e,87,65,0d,00,0a,00,3c,50,00,00"));
        Check(reg.Contains("\"a\\\"b\\\\c\"=hex(1):"));
        Check(reg.Contains("\"Dword\"=dword:ffffffff"));
        Check(reg.Contains("\"Qword\"=hex(b):fe,ff,ff,ff,ff,ff,ff,ff"));
        Check(reg.Contains("\"Binary\"=hex:00,01,ff"));
        Check(reg.Contains("\"Multi\"=hex(7):")&&reg.Contains("\"Expand\"=hex(2):"));
        Reject(()=>Snapshot.RegFile(new[]{all with {Path=@"Software\OtherSoftware"}}));
        Reject(()=>Snapshot.RegFile(new[]{all with {Values=new[]{Text("bad\nname","value")}}}));
        Reject(()=>new SavedValue("bad",RegistryValueKind.None,Array.Empty<string>()).Value());
        var names=typeof(SelfTests).Assembly.GetManifestResourceNames();
        foreach(var name in new[]{"Licenses.SmartZip.txt","Licenses.DotNet-MIT.txt","Licenses.DotNet-ThirdParty.txt","Licenses.CsWinRT.txt"})
            Check(names.Contains(name));
    }
}
