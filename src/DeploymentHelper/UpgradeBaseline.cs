// Shared by preflight and no-install tests. Never infer ownership from a directory alone.
internal static class UpgradeBaseline {
    internal static void RequireCoherent(bool productState, bool package, bool uninstallEntry, bool receipt) {
        if (!(productState || package || uninstallEntry || receipt)) return;
        if (productState && package && uninstallEntry && receipt) return;
        throw new UpgradeBaselineException(
            "检测到安装状态不完整，已停止升级检查，未更改旧版。\n" +
            $"产品状态：{Label(productState)}；Package：{Label(package)}；卸载项：{Label(uninstallEntry)}；已登记路径的收据：{Label(receipt)}。\n\n" +
            "请保留当前程序和日志，先核实缺失信息。不要手动删除目录，也不要直接重装来覆盖问题。");
    }
    static string Label(bool present) => present ? "存在" : "缺失";
}
internal sealed class UpgradeBaselineException(string message) : InvalidOperationException(message);
