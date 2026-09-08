using Microsoft.Win32;
using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

internal sealed record BackupValue(string Name,RegistryValueKind Kind,string[] Data) {
    internal static BackupValue Read(RegistryKey key,string name) {
        var kind=key.GetValueKind(name);var v=key.GetValue(name,null,RegistryValueOptions.DoNotExpandEnvironmentNames);
        return new(name,kind,kind switch {
            RegistryValueKind.String or RegistryValueKind.ExpandString=>new[]{(string)v!},
            RegistryValueKind.DWord=>new[]{((int)v!).ToString(CultureInfo.InvariantCulture)},
            RegistryValueKind.QWord=>new[]{((long)v!).ToString(CultureInfo.InvariantCulture)},
            RegistryValueKind.Binary=>new[]{Convert.ToBase64String((byte[])v!)},
            RegistryValueKind.MultiString=>(string[])v!,
            _=>throw new IOException("Unsupported registry value; upgrade stopped before changes.")});
    }
    internal object Value()=>Kind switch {
        RegistryValueKind.String or RegistryValueKind.ExpandString=>Data.Single(),
        RegistryValueKind.DWord=>int.Parse(Data.Single(),CultureInfo.InvariantCulture),
        RegistryValueKind.QWord=>long.Parse(Data.Single(),CultureInfo.InvariantCulture),
        RegistryValueKind.Binary=>Convert.FromBase64String(Data.Single()),
        RegistryValueKind.MultiString=>Data,
        _=>throw new IOException("Unsupported registry backup.")};
}
internal sealed record BackupKey(string Path,BackupValue[] Values);
internal sealed record BackupFile(string Name,byte[]? Data);
internal sealed record UpgradeBackupData(string Nonce,BackupKey[] Keys,BackupFile[] Files);
[JsonSerializable(typeof(UpgradeBackupData))]
internal partial class UpgradeBackupContext:JsonSerializerContext{}

internal static class UpgradeBackup {
    internal const string StateKey=@"Software\SmartZipModern";
    internal const string UninstallKey=@"Software\Microsoft\Windows\CurrentVersion\Uninstall\{DA975784-DC84-48EF-9A47-F60C0C969280}_is1";
    static readonly string[] Keys={StateKey,UninstallKey};
    // Exact list only: no wildcard restore, arbitrary destination or recursive deletion.
    static readonly string[] Files={"unins000.exe","unins000.dat","unins000.msg",".install-transaction","shortcut-settings","shortcut-uninstall","shortcut-updates"};
    internal static string DirectoryPath(string root,string nonce) {
        if(!Guid.TryParseExact(nonce,"N",out _))throw new IOException("Invalid upgrade backup nonce.");
        return Path.Combine(root,".upgrade-"+nonce);
    }
    internal static string Serialize(UpgradeBackupData data)=>JsonSerializer.Serialize(data,UpgradeBackupContext.Default.UpgradeBackupData);
    internal static UpgradeBackupData Deserialize(string json)=>JsonSerializer.Deserialize(json,UpgradeBackupContext.Default.UpgradeBackupData)??throw new IOException("Empty upgrade backup.");
    static string FilePath(string root,string name) => name switch {
        "shortcut-settings"=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"SmartZip","SmartZip 设置.lnk"),
        "shortcut-uninstall"=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"SmartZip","卸载 SmartZip.lnk"),
        "shortcut-updates"=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"SmartZip","检查更新.lnk"),
        _ when Files.Contains(name)=>Path.Combine(root,name),
        _=>throw new IOException("Unexpected backup file destination.")};
    static BackupKey CaptureKey(string path) {
        using var key=Registry.CurrentUser.OpenSubKey(path)??throw new IOException("Upgrade registry baseline disappeared.");
        if(key.SubKeyCount!=0)throw new IOException("Unexpected registry subkeys; upgrade stopped.");
        return new(path,key.GetValueNames().OrderBy(n=>n,StringComparer.Ordinal).Select(n=>BackupValue.Read(key,n)).ToArray());
    }
    static void NoLinks(string path) {
        for(var p=path;!string.IsNullOrEmpty(p);p=Path.GetDirectoryName(p)!) {
            try {if((File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)throw new IOException("Backup path contains a reparse point.");}
            catch(FileNotFoundException){}catch(DirectoryNotFoundException){}
        }
    }
    internal static void Capture(string root,string nonce) {
        var folder=DirectoryPath(root,nonce);NoLinks(folder);InstallPath.RequireUnused(folder);
        var files=Files.Select(name=>{
            var path=FilePath(root,name);NoLinks(path);
            byte[]? bytes;try{bytes=File.ReadAllBytes(path);}catch(FileNotFoundException){bytes=null;}catch(DirectoryNotFoundException){bytes=null;}
            return new BackupFile(name,bytes);
        }).ToArray();
        var json=Serialize(new(nonce,Keys.Select(CaptureKey).ToArray(),files));
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder,"backup.json"),json);
        if(File.ReadAllText(Path.Combine(folder,"backup.json"))!=json)throw new IOException("Upgrade backup read-back failed.");
    }
    internal static UpgradeBackupData Read(string root,string nonce) {
        var file=Path.Combine(DirectoryPath(root,nonce),"backup.json");NoLinks(file);
        var data=Deserialize(File.ReadAllText(file));ValidateData(data,nonce);return data;
    }
    internal static void ValidateData(UpgradeBackupData data,string nonce) {
        if(data.Nonce!=nonce||!data.Keys.Select(k=>k.Path).SequenceEqual(Keys)||!data.Files.Select(f=>f.Name).SequenceEqual(Files))
            throw new IOException("Upgrade backup identity/scope mismatch.");
    }
    internal static void Restore(string root,string nonce) {
        var data=Read(root,nonce);
        foreach(var file in data.Files) {
            var path=FilePath(root,file.Name);NoLinks(path);
            if(file.Data==null){if(File.Exists(path))File.Delete(path);continue;}
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);File.WriteAllBytes(path,file.Data);
            if(!File.ReadAllBytes(path).SequenceEqual(file.Data))throw new IOException("Uninstall metadata restoration failed.");
        }
        foreach(var saved in data.Keys) {
            using var key=Registry.CurrentUser.CreateSubKey(saved.Path);
            if(key.SubKeyCount!=0)throw new IOException("Unexpected subkeys during rollback.");
            foreach(var name in key.GetValueNames())if(!saved.Values.Any(v=>v.Name==name))key.DeleteValue(name);
            foreach(var value in saved.Values)key.SetValue(value.Name,value.Value(),value.Kind);
            key.Flush();
            var captured=CaptureKey(saved.Path);
            for(int i=0;i<saved.Values.Length;i++) {
                var expected=saved.Values[i];var actual=captured.Values.Single(v=>v.Name==expected.Name);
                if(actual.Kind!=expected.Kind||!actual.Data.SequenceEqual(expected.Data))throw new IOException("Registry restoration verification failed.");
            }
            if(captured.Values.Length!=saved.Values.Length)throw new IOException("Registry restoration contains unexpected values.");
        }
    }
    internal static void Discard(string root,string nonce) {
        var folder=DirectoryPath(root,nonce);NoLinks(folder);
        try{_=File.GetAttributes(folder);}catch(FileNotFoundException){return;}catch(DirectoryNotFoundException){return;}
        if(Directory.GetFileSystemEntries(folder).Length==0){Directory.Delete(folder,false);return;}
        _=Read(root,nonce);
        if(Directory.GetFileSystemEntries(folder).Length!=1)throw new IOException("Unexpected files in backup; retained.");
        File.Delete(Path.Combine(folder,"backup.json"));Directory.Delete(folder,false);
    }
}
