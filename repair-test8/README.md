# test8 定点残留修复

仅针对 SmartZip Modern 0.1.0.7 在本机卸载后遗留的 HKCU 产品状态和卸载项。不是通用清理器，也不是新版安装包。

## 使用

1. 关闭 SmartZip 安装器和只读诊断窗口。
2. 在资源管理器中双击 `dist\SmartZip-Repair-test8.exe`，不要选择“以管理员身份运行”。
3. 核验通过后会请求确认。选择“是”才会先备份、再清理；选择“否”不修改注册表。
4. 保留最终结果截图和日志，先不要重新安装。需要通过同一启动环境复查安装器后再继续。

如果提示“没有发现目标残留”，只表示该进程看不到目标项，不能证明其他启动环境没有残留。若任意身份、版本、路径或 Package 检查不符，工具会停止。

## 操作边界

只允许删除以下两个当前用户键（非递归）：

- `HKCU\Software\SmartZipModern`
- `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{DA975784-DC84-48EF-9A47-F60C0C969280}_is1`

清理要求旧、新默认安装目录均不存在，当前用户没有 SmartZip.Modern Package；现存状态键必须匹配 test8 版本、发布者、用户 SID、安装路径和证书指纹，卸载项必须匹配产品、版本及卸载程序路径。32/64 位视图必须一致；出现子键会拒绝处理。

程序不删除文件，不修改证书、Package、COM、系统 Feature 或原 UnZip 菜单。仅写入本工具的日志及备份，并按确认结果删除指定残留键。

备份：`%LOCALAPPDATA%\SmartZip\RepairBackups\时间-随机编号\` 下的 UTF-16 `.reg` 和 JSON 快照。
日志：`%TEMP%\SmartZip-Repair-test8-进程号.log`。

删除前再次比较快照，删除后立即复查两个视图。中途失败会尝试恢复已删除键的原始值及值类型；若存在外部修改，停止自动恢复并保留备份，不能宣称回滚完整。备份不含自定义注册表 ACL，请勿把本工具用于其他产品或版本。

## 构建与检查

在项目根目录执行 `pwsh -NoProfile -File repair-test8\build.ps1`。使用项目现有 .NET SDK、Windows SDK 签名工具、开发签名材料及许可证文件。不会导入任何证书。

`--self-test` 只做内存中的身份限制、导出格式、JSON 往返及路径白名单测试；构建前后都会运行。`--inspect` 只读检查并写日志，不显示确认框、不执行清理。仅不带参数的交互运行允许请求清理确认。

这是未受公共信任的开发签名工具，不承诺没有 SmartScreen 提示。MIT/.NET/CsWinRT 的许可文本作为 `Licenses.*` 资源嵌入 EXE，原文见本项目 `LICENSE`、`licenses\CsWinRT.txt` 和构建输入 `build\payload\Licenses`。工具自带所需 .NET 运行时，无需用户安装 SDK。
