using System.Text.Json;
using System.Text.RegularExpressions;

internal sealed record UpdateRelease(string Version,string FileName,Uri Download,long Size,string Sha256,string Notes) {
    internal const string Repository="https://github.com/yueyangcode/SmartZip";
    internal const string LatestApi="https://api.github.com/repos/yueyangcode/SmartZip/releases/latest";
    internal const long MaxDownload=128*1024*1024;
    internal static Version ParseVersion(string tag) {
        var value=tag.StartsWith('v')?tag[1..]:tag;
        if(!System.Version.TryParse(value,out var v)||v.Build<0||v.Revision<0||v.ToString(4)!=value||
           new[]{v.Major,v.Minor,v.Build,v.Revision}.Any(n=>n>65535))throw new IOException("发布版本号格式不正确。");
        return v;
    }
    internal static UpdateRelease? Parse(string json,string current) {
        using var doc=JsonDocument.Parse(json);var r=doc.RootElement;
        if(r.GetProperty("draft").GetBoolean()||r.GetProperty("prerelease").GetBoolean())return null;
        string tag=r.GetProperty("tag_name").GetString()??"";
        var version=ParseVersion(tag);
        if(tag!="v"+version.ToString(4))throw new IOException("发布标签不是规范的正式版本号。");
        if(version<=ParseVersion(current))return null;
        string name=$"SmartZipSetup-{version}-x64.exe";
        var assets=r.GetProperty("assets").EnumerateArray().Where(a=>a.GetProperty("name").GetString()==name).ToArray();
        if(assets.Length!=1)throw new IOException("正式发布中缺少唯一的 Windows x64 安装包。");
        var a=assets[0];long size=a.GetProperty("size").GetInt64();
        string expected=$"{Repository}/releases/download/{tag}/{name}";
        string digest=a.GetProperty("digest").GetString()??"";
        if(a.GetProperty("state").GetString()!="uploaded"||size<=0||size>MaxDownload||
           a.GetProperty("browser_download_url").GetString()!=expected||!Regex.IsMatch(digest,@"\Asha256:[0-9a-fA-F]{64}\z"))
            throw new IOException("更新包地址、大小或 SHA-256 不符合发布要求。");
        string notes=r.TryGetProperty("body",out var body)?body.GetString()??"":"";
        // Plain text only: never interpret release notes as HTML, links or commands.
        notes=new string(notes.Where(c=>!char.IsControl(c)||c=='\n'||c=='\t').Take(4000).ToArray());
        return new(version.ToString(4),name,new Uri(expected),size,digest[7..].ToUpperInvariant(),notes);
    }
    internal static bool DownloadRedirectAllowed(Uri uri)=>uri.Scheme=="https"&&uri.IsDefaultPort&&uri.UserInfo==""&&uri.Fragment==""&&
        (uri.Host=="release-assets.githubusercontent.com"||uri.Host=="objects.githubusercontent.com");
}
