# SmartZip 0.1.0.11 升级安全修复

日期：2026-09-09。此记录区分代码/隔离测试和真实安装验收。

## 构建产物

- 安装包：`dist/SmartZipSetup-0.1.0.11-test.exe`
- 大小：14,337,736 字节（13.67 MiB）
- SHA-256：`9268756A6477D2090B31C42B648ED84361FCA3A903E0264B0409F73C1C4DF5F1`
- 当前机器 Authenticode 检查：Valid；签名者 `CN=SmartZip Modern Evaluation`，指纹 `A1709CED9DB02150E2FB40CE6496BD1938D89195`。
- 仍为测试签名，不代表另一台机器已建立信任，不是正式发布签名。
- per-user 安装。证书、权限及目录设计不变；构建阶段没有运行安装包、注册 Package、导入证书或结束 Explorer。后续本机验收另记于下文。
- 原 0.1.0.10 安装包未覆盖，SHA-256 仍为 `1B64E06803D25F09098A6B30AFA6C38BE15C4B121F5FDE351DEE7A101BA6FB25`。

## 实际故障证据

0.1.0.10 的安装日志和 AppXDeploymentServer 事件记录确认：从 0.1.0.8 更新时出现 `0x80073D02`，被占用的是旧版 SmartZip.Modern Package。

失败后 0.1.0.10 目录被清理，0.1.0.8 文件和原收据标记仍在，但 Windows 返回旧包 `Modified, NeedsRemediation`。所以原来的 `UPGRADE_ROLLBACK_COMPLETE` 不足以证明恢复健康。

源码确认预检查会通过 CoCreateInstance 激活旧版 COM 服务，即使释放接口也可能留下仍占用 Package 的宿主进程。日志没有精确到唯一占用进程的证据，因此不将其断言为本次失败的唯一来源。

## 修复内容

1. 所有安装事务校验不再激活 packaged COM。保留包身份、外部位置、PackagedCom 注册和菜单声明验证；实际 IExplorerCommand 行为通过独立 DLL 测试及后续 Explorer 验收验证。
2. 预检查、提交、完成、回滚和更新后验证均检查 `Package.Status.VerifyIsOK()`，同时拒绝 NeedsRemediation、Modified、Tampered、部分暂存或正在 servicing/deployment 的状态。安装前已异常的包会在写入前停止，不在预检查中自动修复。
3. 回滚不再仅根据版本号决定是否恢复。即使仍为旧版，只要健康状态异常，也尝试重新部署本次事务保存并验证 SHA-256 的旧 Identity.msix；重新枚举后必须通过健康/注册检查才可继续清理及报告成功。Windows 若仍拒绝恢复，停止删除依赖文件和备份。
4. 回滚不完整时持久保留专用恢复记录（验证当前事务标记，CreateNew，不覆盖既有记录）；记录写入失败也记录日志，不伪报成功，不擅自清理依赖资源。
5. 明确关闭 ForceAppShutdown、ForceTargetAppShutdown 和延迟注册。占用错误提供中文说明；回滚失败的提示优先于“关闭程序再试”。未完成注册不允许提交安装成功。

不承诺强行解决所有占用：用户正在解压、设置窗口或已有 COM 宿主都仍可能阻止系统更新。此版不增加强杀、重启、自动修复证书或注册表绕行。

## 验证结果

- 完整构建 PASS；部署助手发布/裁剪警告按错误处理。
- 128 种健康状态组合、12 种恢复判定、同版本异常恢复成功/仍异常/抛错分支 PASS。
- 8 个安装安全源代码变异测试 PASS：保护无 COM 激活、无强杀/延迟注册、健康校验、恢复记录、注册完成检查。
- 占用异常、嵌套 HRESULT、回滚失败优先级和中文提示测试 PASS。
- 既有中文向导/路径、独立 COM/参数、身份/UAC、收据、事务、跨进程管道、更新器哈希/签名/活动锁及发布门禁 PASS。
- 构建保留两条已有 C++ COM 导出重复声明警告，无新增构建失败。
- 构建时的只读本机检查实际调用新健康判定：当时旧 0.1.0.8 的 Verified=False、NeedsRemediation=True、Modified=True，被正确拒绝；该次检查没有激活 COM、重新注册、修复或修改证书。

构建日志在 `build/tests/build-0.1.0.11.log`（本地，不提交）。

复现构建与隔离测试：

```powershell
pwsh -NoProfile -File .\build.ps1 -Signing Test -Version 0.1.0.11
dotnet run --project .\tests\UpgradeTests -c Release
pwsh -NoProfile -File .\tests\DeploymentSafety.Tests.ps1
```

专用于已安装本项目测试版的只读健康检查（不加载 COM、不修复）：

```powershell
dotnet run --project .\tests\UpgradeTests -c Release -- --read-only-installed-health
```

## 构建后的本机验收（2026-09-09）

用户授权备份并重新部署本项目旧 0.1.0.8 Package，恢复健康后，使用上述哈希的安装包升级到 0.1.0.11。用户确认安装成功；本机安装日志确认旧/新版健康检查通过，事务完成 PREPARED、COMMITTED 和 FINALIZED。随后用户反馈本机卸载、重装及使用无问题，但未独立采集该轮完整前后快照。

旧包人工恢复与本版自动回滚是两项不同操作。真实故障回滚、占用重试、0.1.0.11 第二台干净机器及 GitHub 自动更新闭环仍待验收，见 [验收记录](TESTED-BASELINE.md)。

发布准备沿用用户测试过的安装包，不因补充文档而重新构建。源码另补充了只读健康测试的外部路径输出；该测试程序不随安装器分发。重新构建会生成新的签名和构建元数据，不应期待与此测试产物逐字节一致。

## 依据

- [Microsoft PackageStatus.VerifyIsOK](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.packagestatus.verifyisok?view=winrt-26100)：健康判定，而非仅检查版本存在。
- [Microsoft PackageStatus](https://learn.microsoft.com/zh-cn/uwp/api/windows.applicationmodel.packagestatus?view=winrt-26100)：状态只读，重新获取才能得到新状态。
- [Microsoft ForceUpdateFromAnyVersion](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.addpackageoptions.forceupdatefromanyversion?view=winrt-26100)：仅用于恢复事务保存的指定旧版本，不代表强行结束应用。
