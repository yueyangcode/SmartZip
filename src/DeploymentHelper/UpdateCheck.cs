using System.Diagnostics;
using System.Net;
using System.Text.Json;

internal static class UpdateCheck {
    internal static Version ParseVersion(string tag) {
        var value = tag.StartsWith('v') ? tag[1..] : tag;
        if (!Version.TryParse(value, out var version)) throw new IOException("发布版本号格式不正确。");
        return new Version(version.Major, version.Minor, Math.Max(version.Build, 0), Math.Max(version.Revision, 0));
    }
    // Check outside Explorer; never download or execute a remote executable here.
    internal static async Task Run(bool quiet, Action<string> log, Func<string, bool> confirm) {
        var state = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SmartZip", "UpdateCheck");
        var stamp = Path.Combine(state, "last-check");
        if (quiet && File.Exists(stamp) && DateTime.UtcNow - File.GetLastWriteTimeUtc(stamp) < TimeSpan.FromDays(1)) return;
        Directory.CreateDirectory(state);
        File.WriteAllText(stamp, DateTime.UtcNow.ToString("O"));
        using var handler = new HttpClientHandler { AllowAutoRedirect = false };
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(10) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("SmartZip/" + ProductIdentity.Version);
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        using var response = await client.GetAsync("https://api.github.com/repos/yueyangcode/SmartZip/releases/latest", HttpCompletionOption.ResponseHeadersRead, deadline.Token);
        if (response.StatusCode == HttpStatusCode.NotFound) { log("No public stable release available."); if (!quiet) confirm("目前没有可用的公开正式版本。"); return; }
        response.EnsureSuccessStatusCode();
        using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
        using var body = new MemoryStream();
        var buffer = new byte[8192];
        int count;
        while ((count = await stream.ReadAsync(buffer, deadline.Token)) != 0) {
            if (body.Length + count > 1024 * 1024) throw new IOException("发布信息超过大小限制。");
            body.Write(buffer, 0, count);
        }
        using var json = JsonDocument.Parse(body.ToArray());
        var root = json.RootElement;
        if (root.GetProperty("draft").GetBoolean() || root.GetProperty("prerelease").GetBoolean()) return;
        var tag = root.GetProperty("tag_name").GetString() ?? "";
        var latest = ParseVersion(tag);
        var current = ParseVersion(ProductIdentity.Version);
        if (latest <= current) { if (!quiet) confirm("当前已是最新版本。"); return; }
        if (confirm($"发现 SmartZip 新版本 {latest}，当前版本为 {current}。\n\n是否打开官方 GitHub 发布页面查看说明并下载安装？"))
            Process.Start(new ProcessStartInfo("https://github.com/yueyangcode/SmartZip/releases/tag/" + Uri.EscapeDataString(tag)) { UseShellExecute = true });
    }
}
