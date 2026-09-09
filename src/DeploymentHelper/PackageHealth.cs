using Windows.ApplicationModel;

internal readonly record struct PackageHealth(bool Verified, bool NeedsRemediation, bool Modified,
    bool Tampered, bool IsPartiallyStaged, bool DeploymentInProgress, bool Servicing) {
    internal static PackageHealth Read(PackageStatus status) => new(status.VerifyIsOK(),
        status.NeedsRemediation,status.Modified,status.Tampered,status.IsPartiallyStaged,
        status.DeploymentInProgress,status.Servicing);
    internal bool IsHealthy => Verified && !NeedsRemediation && !Modified && !Tampered &&
        !IsPartiallyStaged && !DeploymentInProgress && !Servicing;
    internal void RequireHealthy(string package) {
        if(!IsHealthy)throw new PackageHealthException(package+": "+this);
    }
}

internal sealed class PackageHealthException(string details) : IOException(details);

internal sealed class RollbackIncompleteException(Exception primary,Exception cleanup)
    : AggregateException("SmartZip rollback did not restore a verified healthy baseline.",primary,cleanup);

internal static class DeploymentFailure {
    internal const int PackagesInUse=unchecked((int)0x80073D02);
    internal static bool HasCode(Exception error,int code) => error.HResult==code ||
        (error is AggregateException aggregate ? aggregate.InnerExceptions.Any(e=>HasCode(e,code)) :
        error.InnerException!=null && HasCode(error.InnerException,code));
    internal static string? UserMessage(Exception error) {
        // A failed rollback takes priority over the original busy error: retry is not safe.
        if(error is RollbackIncompleteException)
            return "安装未成功，回滚也未能确认恢复到健康状态。已保留恢复所需资料，请勿卸载、手动删文件或继续重试。\n请将日志提供给开发者，先检查并恢复本项目 Package。";
        if(error is PackageHealthException)
            return "检测到 SmartZip 的 Package 状态异常或仍在部署中，已停止操作。版本号和 COM 注册存在不代表安装完整。\n请保留日志，先检查并恢复本项目 Package；不要反复安装、强制清理或修改证书。";
        if(HasCode(error,PackagesInUse))
            return "SmartZip 的程序包资源正在使用中，本次操作未完成（0x80073D02）。\n请等待解压完成，关闭 SmartZip 设置及相关右键菜单后退出安装程序。确认原安装健康后再重试；仍被占用时可保存工作并手动重启 Windows。\n安装器不会强制结束 Explorer 或解压任务。";
        return null;
    }
}
