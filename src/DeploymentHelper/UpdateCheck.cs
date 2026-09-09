using System.Diagnostics;
using System.Net;
using System.Security.Cryptography;

internal static class UpdateCheck {
    internal static string StateDirectory=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"SmartZip","UpdateCheck");
    internal static bool Due(DateTime last,DateTime now)=>(now-last)<TimeSpan.Zero||(now-last)>=TimeSpan.FromDays(1);
    internal static ProcessStartInfo InstallerStart(string file,string root,string log) {
        var info=new ProcessStartInfo(file){UseShellExecute=true,WindowStyle=ProcessWindowStyle.Hidden,WorkingDirectory=Path.GetDirectoryName(file)!};
        foreach(var a in new[]{"/VERYSILENT","/SUPPRESSMSGBOXES","/SP-","/NORESTART","/NOCLOSEAPPLICATIONS","/NOFORCECLOSEAPPLICATIONS","/RESTARTEXITCODE=3010","/DIR="+root,"/LOG="+log})info.ArgumentList.Add(a);
        return info;
    }
    internal static async Task Run(bool quiet,string root,Action<string> log,Action revalidate,Action<string> verifyInstalled) {
        bool accepted=false;FileStream? single=null;
        try {
            UpdateActivity.NoLinks(StateDirectory);Directory.CreateDirectory(StateDirectory);
            var lockFile=Path.Combine(StateDirectory,"check.lock");UpdateActivity.NoLinks(lockFile);
            try{single=new FileStream(lockFile,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);}
            catch(IOException ex)when(UpdateActivity.IsSharingViolation(ex)){if(!quiet)UpdateDialog.Info("已有更新检查或更新任务正在运行。");return;}
            var stamp=Path.Combine(StateDirectory,"last-check");var skipped=Path.Combine(StateDirectory,"skipped-version");
            UpdateActivity.NoLinks(stamp);UpdateActivity.NoLinks(skipped);
            if(quiet&&File.Exists(stamp)&&!Due(File.GetLastWriteTimeUtc(stamp),DateTime.UtcNow))return;
            File.WriteAllText(stamp,DateTime.UtcNow.ToString("O"));
            using var client=UpdateDownload.Client();client.DefaultRequestHeaders.UserAgent.ParseAdd("SmartZip/"+ProductIdentity.Version);
            client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
            using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(15));
            using var response=await client.GetAsync(UpdateRelease.LatestApi,HttpCompletionOption.ResponseHeadersRead,timeout.Token);
            if(response.StatusCode==HttpStatusCode.NotFound){log("UPDATE_NO_STABLE_RELEASE");if(!quiet)UpdateDialog.Info("目前没有可用的公开正式版本。");return;}
            response.EnsureSuccessStatusCode();
            using var input=await response.Content.ReadAsStreamAsync(timeout.Token);using var body=new MemoryStream();
            var buffer=new byte[8192];int count;
            while((count=await input.ReadAsync(buffer,timeout.Token))!=0){if(body.Length+count>1024*1024)throw new IOException("发布信息超过大小限制。");body.Write(buffer,0,count);}
            var release=UpdateRelease.Parse(System.Text.Encoding.UTF8.GetString(body.ToArray()),ProductIdentity.Version);
            if(release==null){if(!quiet)UpdateDialog.Info("当前没有比已安装版本更新的正式版本。");return;}
            if(quiet&&File.Exists(skipped)&&File.ReadAllText(skipped)==release.Version)return;
            int choice=UpdateDialog.Ask(release,ProductIdentity.Version);
            if(choice==UpdateDialog.Skip){File.WriteAllText(skipped,release.Version);log("UPDATE_SKIPPED="+release.Version);return;}
            if(choice!=UpdateDialog.Install)return;
            accepted=true;log("UPDATE_CONSENT="+release.Version);
            bool restart=false;
            UpdateDialog.Run(async operation=>{restart=await Install(client,release,root,operation,log,revalidate,verifyInstalled);});
            UpdateDialog.Info("SmartZip 已更新至 "+release.Version+"，安装位置和用户配置已保留。"+(restart?"\n系统提示需要重启，请在方便时手动重启。":""));
        }catch(OperationCanceledException){log("UPDATE_CANCELLED_OR_TIMED_OUT");if(accepted||!quiet)UpdateDialog.Info("更新已取消或等待超时。未完成的下载不会执行。");}
        catch(Exception ex){
            // Do not log redirected asset URLs: they can contain expiring access tokens.
            log("UPDATE_FAILED="+ex.GetType().Name+"; code=0x"+ex.HResult.ToString("X8"));
            if(accepted||!quiet)UpdateDialog.Info("更新未能完成。请保留日志，不要手动删除安装目录或修改证书。\n\n"+
                (ex is IOException?ex.Message:"网络或系统验证失败，请稍后重试。")+"\n\n更新记录位于用户临时目录中的 SmartZip 日志。",true);
        }finally{single?.Dispose();}
    }
    static async Task<bool> Install(HttpClient client,UpdateRelease release,string root,UpdateOperation operation,Action<string> log,Action revalidate,Action<string> verifyInstalled) {
        string folder=Path.Combine(StateDirectory,"download-"+Guid.NewGuid().ToString("N"));
        UpdateActivity.NoLinks(folder);Directory.CreateDirectory(folder);
        string file=Path.Combine(folder,release.FileName);bool clean=true;bool restart=false;
        string installLog=Path.Combine(Path.GetTempPath(),"SmartZip-update-"+Guid.NewGuid().ToString("N")+".log");
        try {
            using(var deadline=CancellationTokenSource.CreateLinkedTokenSource(operation.Token)) {
                deadline.CancelAfter(TimeSpan.FromMinutes(10));
                using var response=await UpdateDownload.Open(client,release,deadline.Token);
                using var input=await response.Content.ReadAsStreamAsync(deadline.Token);
                using var output=new FileStream(file,FileMode.CreateNew,FileAccess.Write,FileShare.None,65536,true);
                await UpdateDownload.CopyVerified(input,output,release.Size,release.Sha256,
                    percent=>operation.Report($"正在下载 SmartZip {release.Version}：{percent}%",percent),deadline.Token);
            }
            // Preserve Internet-zone provenance; do not suppress Windows reputation checks.
            File.WriteAllText(file+":Zone.Identifier","[ZoneTransfer]\r\nZoneId=3\r\nHostUrl="+release.Download.AbsoluteUri+"\r\n");
            using(var pinned=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.Read)) {
                if(pinned.Length!=release.Size||Convert.ToHexString(SHA256.HashData(pinned))!=release.Sha256)throw new IOException("下载文件在校验前发生变化，已停止更新。");
                operation.Report("正在验证 Windows 数字签名及发布者……",100);
                UpdateSignature.Verify(file,release.Version,ProductIdentity.Publisher,ProductIdentity.CertificateSha256,ProductIdentity.TestSigned);
                operation.Token.ThrowIfCancellationRequested();
                using var idle=await UpdateActivity.WaitForIdle(Path.Combine(StateDirectory,"activity.lock"),operation.Token,
                    ()=>operation.Report("等待正在进行的 SmartZip 操作结束。可以取消更新，解压不会被中断。",100));
                revalidate();operation.BeginInstall();
                log("UPDATE_INSTALL_LOG="+installLog);
                using var process=Process.Start(InstallerStart(file,root,installLog));
                if(process==null){clean=false;throw new IOException("无法取得安装进程状态。已保留下载文件；请先确认安装程序是否仍在运行。");}
                clean=false; // Retain the backing EXE if process monitoring itself fails.
                await process.WaitForExitAsync(); // Never kill or cancel an installer halfway through rollback/commit.
                clean=true;
                log("UPDATE_INSTALL_EXIT="+process.ExitCode);
                if(process.ExitCode!=0&&process.ExitCode!=3010)throw new IOException("安装器返回失败（"+process.ExitCode+"）。请查看日志确认回滚结果：\n"+installLog);
                verifyInstalled(release.Version);restart=process.ExitCode==3010;
                log("UPDATE_VERIFIED="+release.Version);
            }
        }finally {
            if(clean)try {
                UpdateActivity.NoLinks(file);if(File.Exists(file))File.Delete(file);
                Directory.Delete(folder,false);
            }catch(Exception ex)when(ex is IOException or UnauthorizedAccessException){log("UPDATE_CACHE_RETAINED="+folder);}
        }
        return restart;
    }
}
