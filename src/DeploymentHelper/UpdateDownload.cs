using System.Net;
using System.Security.Cryptography;

internal static class UpdateDownload {
    internal static HttpClient Client()=>new(new HttpClientHandler{AllowAutoRedirect=false,UseCookies=false}){Timeout=Timeout.InfiniteTimeSpan};
    internal static async Task<HttpResponseMessage> Open(HttpClient client,UpdateRelease release,CancellationToken cancel) {
        var uri=release.Download;
        for(int redirects=0;redirects<=3;redirects++) {
            var response=await client.GetAsync(uri,HttpCompletionOption.ResponseHeadersRead,cancel);
            if(new[]{301,302,303,307,308}.Contains((int)response.StatusCode)) {
                var location=response.Headers.Location;response.Dispose();
                if(location==null)throw new IOException("下载重定向缺少目标。");
                var next=location.IsAbsoluteUri?location:new Uri(uri,location);
                if(!UpdateRelease.DownloadRedirectAllowed(next))throw new IOException("更新下载被重定向到未允许的地址，已停止。");
                uri=next;continue;
            }
            if(response.StatusCode!=HttpStatusCode.OK||
               (response.Content.Headers.ContentLength is long length&&length!=release.Size)) {
                response.Dispose();throw new IOException("更新下载返回错误或文件长度不符。");
            }
            return response;
        }
        throw new IOException("更新下载重定向次数过多。");
    }
    internal static async Task CopyVerified(Stream input,Stream output,long expectedSize,string expectedHash,Action<int> progress,CancellationToken cancel) {
        if(expectedSize<=0||expectedSize>UpdateRelease.MaxDownload)throw new IOException("更新文件大小超出限制。");
        using var hash=IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var bytes=new byte[65536];long total=0;int count;
        while((count=await input.ReadAsync(bytes,cancel))!=0) {
            total+=count;if(total>expectedSize)throw new IOException("下载文件超过声明大小。");
            hash.AppendData(bytes,0,count);await output.WriteAsync(bytes.AsMemory(0,count),cancel);
            progress((int)(total*100/expectedSize));
        }
        if(total!=expectedSize||!string.Equals(Convert.ToHexString(hash.GetHashAndReset()),expectedHash,StringComparison.Ordinal))
            throw new IOException("更新文件不完整或 SHA-256 不匹配，未执行安装。");
        await output.FlushAsync(cancel);
    }
}
