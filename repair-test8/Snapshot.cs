using Microsoft.Win32;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

internal sealed record SavedValue(string Name, RegistryValueKind Kind, string[] Data) {
    internal static SavedValue Read(RegistryKey key,string name) {
        var kind=key.GetValueKind(name);
        var value=key.GetValue(name,null,RegistryValueOptions.DoNotExpandEnvironmentNames);
        var data=kind switch {
            RegistryValueKind.String or RegistryValueKind.ExpandString => new[]{(string)value!},
            RegistryValueKind.MultiString => (string[])value!,
            RegistryValueKind.DWord => new[]{((int)value!).ToString(CultureInfo.InvariantCulture)},
            RegistryValueKind.QWord => new[]{((long)value!).ToString(CultureInfo.InvariantCulture)},
            RegistryValueKind.Binary => new[]{Convert.ToBase64String((byte[])value!)},
            _ => throw new IOException("注册表值类型不受支持，未进行清理。")
        };
        return new(name,kind,data);
    }
    internal object Value() => Kind switch {
        RegistryValueKind.String or RegistryValueKind.ExpandString => Data.Single(),
        RegistryValueKind.MultiString => Data,
        RegistryValueKind.DWord => int.Parse(Data.Single(),CultureInfo.InvariantCulture),
        RegistryValueKind.QWord => long.Parse(Data.Single(),CultureInfo.InvariantCulture),
        RegistryValueKind.Binary => Convert.FromBase64String(Data.Single()),
        _ => throw new IOException("不支持的备份类型。")
    };
}
internal sealed record SavedKey(string Path,SavedValue[] Values) {
    internal string? Text(string name) => Values.SingleOrDefault(x=>x.Name==name)?.Value() as string;
}
[JsonSerializable(typeof(SavedKey[]))]
internal partial class BackupJson : JsonSerializerContext { }

internal static class Snapshot {
    internal static SavedKey? Read(RegistryKey hive,string path) {
        using var key=hive.OpenSubKey(path);
        if(key==null)return null;
        if(key.SubKeyCount!=0)throw new IOException("项目键存在未预期的子键，已停止清理。");
        return new(path,key.GetValueNames().OrderBy(x=>x,StringComparer.Ordinal).Select(n=>SavedValue.Read(key,n)).ToArray());
    }
    internal static string Json(SavedKey[] keys)=>JsonSerializer.Serialize(keys,BackupJson.Default.SavedKeyArray);
    internal static bool Same(SavedKey? a,SavedKey? b)=>Json(a==null?Array.Empty<SavedKey>():new[]{a})==Json(b==null?Array.Empty<SavedKey>():new[]{b});
    static string Quote(string name) {
        if(name.Contains('\r')||name.Contains('\n')||name.Contains('\0'))throw new IOException("注册表名称不能安全导出，已停止。");
        return "\""+name.Replace("\\","\\\\").Replace("\"","\\\"")+"\"";
    }
    static string Hex(byte[] bytes)=>string.Join(",",bytes.Select(x=>x.ToString("x2")));
    internal static string RegFile(SavedKey[] keys) {
        var text=new StringBuilder("Windows Registry Editor Version 5.00\r\n\r\n");
        foreach(var key in keys){
            RepairPolicy.RequireAllowedKey(key.Path);
            text.Append("[HKEY_CURRENT_USER\\").Append(key.Path).Append("]\r\n");
            foreach(var item in key.Values){
                text.Append(item.Name.Length==0?"@":Quote(item.Name)).Append('=');
                var value=item.Value();
                // Hex encodings preserve Unicode, newlines, nulls and original value kinds.
                text.Append(item.Kind switch {
                    RegistryValueKind.String => "hex(1):"+Hex(Encoding.Unicode.GetBytes((string)value+"\0")),
                    RegistryValueKind.ExpandString => "hex(2):"+Hex(Encoding.Unicode.GetBytes((string)value+"\0")),
                    RegistryValueKind.MultiString => "hex(7):"+Hex(Encoding.Unicode.GetBytes(string.Join("\0",(string[])value)+"\0\0")),
                    RegistryValueKind.DWord => "dword:"+unchecked((uint)(int)value).ToString("x8"),
                    RegistryValueKind.QWord => "hex(b):"+Hex(BitConverter.GetBytes((long)value)),
                    RegistryValueKind.Binary => "hex:"+Hex((byte[])value),
                    _ => throw new IOException("Unsupported backup value")
                }).Append("\r\n");
            }
            text.Append("\r\n");
        }
        return text.ToString();
    }
}
