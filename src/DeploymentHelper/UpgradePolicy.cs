internal static class UpgradePolicy {
    internal static bool NeedsPackageRestore(int count,bool oldVersionPresent,bool oldHealthy) =>
        count!=1||!oldVersionPresent||!oldHealthy;
    internal static Version VersionNumber(string text) {
        if(!Version.TryParse(text,out var value)||value.Build<0||value.Revision<0||value.ToString(4)!=text||
           new[]{value.Major,value.Minor,value.Build,value.Revision}.Any(p=>p>65535))
            throw new UpgradeBaselineException("安装版本号无效，已停止操作。");
        return value;
    }
    internal static void RequireNewer(string previous,string next) {
        if(VersionNumber(previous)<new Version(0,1,0,8))
            throw new UpgradeBaselineException("自动升级从 0.1.0.8 起支持；更早的测试版需要先通过正常卸载入口移除。");
        if(VersionNumber(next)<=VersionNumber(previous))
            throw new UpgradeBaselineException("当前版本无需重复安装，或所选安装包比当前版本更旧。请选择较新的安装包。");
    }
    internal static void RequireReceipt(Journal receipt,string root,string sid) {
        if(!Guid.TryParseExact(receipt.Nonce,"N",out _)||receipt.UserSid!=sid||
           !string.Equals(receipt.InstallRoot,root,StringComparison.OrdinalIgnoreCase))
            throw new UpgradeBaselineException("安装收据的目录或用户身份不一致，已保留原版并停止升级。");
    }
}
