# 确认后后台更新（当前 0.1.0.11）

更新器始于 0.1.0.10；0.1.0.11 补充安装与回滚的 Package 健康校验。

## 用户行为

使用已安装的 SmartZip 时检查 GitHub，每天最多一次；手动「检查更新」不受日期或跳过版本限制。无常驻服务、计划任务、遥测上传或 GitHub Token。

只读取 `yueyangcode/SmartZip` 最新公开正式 Release。源码提交、草稿、预发布不会触发更新。弹窗显示版本、大小及纯文本更新说明，提供「立即更新 / 稍后提醒 / 跳过此版本」。后两项不下载，稍后到下一检查周期再提醒，跳过只针对该版本。

明确确认后才下载，显示进度。下载/校验/等待解压阶段可取消；进入安装后取消按钮停用，避免强杀破坏事务。校验过程取消会等当前 Windows 验签返回后退出，不中断系统安全检查。

更新持有独占工作锁，SmartZip 启动器持有共享工作锁。当前解压保持运行，更新等待它自然结束；安装期间新请求会提示稍后重试。锁机制从 0.1.0.10 起生效，不追溯控制旧启动器或用户独立打开的第三方压缩软件。

## 下载与信任

- 标签必须为 `v<四段版本号>`，且比当前版本新。
- 安装包名必须为 `SmartZipSetup-<四段版本号>-x64.exe`，唯一且上传完成。
- 初始下载地址必须是该仓库和标签下的规范地址，不能由 Release 指定任意外部 EXE。
- 只允许 HTTPS 及明确的 GitHub 资产 CDN 主机，最多三次重定向，不携带令牌/cookie，不在日志中记录带临时签名参数的 CDN URL。
- 元信息上限 1 MiB，安装包上限 128 MiB，下载总时限十分钟；流式核对长度和 SHA-256，取消、截断或超长文件不得执行。
- 校验后以拒绝写入/删除的共享只读句柄固定安装包，再次计算哈希；调用 WinVerifyTrust 验证实际 Authenticode 签名并取得已验证签名者。
- 签名 Subject 和证书 SHA-256 必须与当前构建固定身份一致，同时检查产品名、版本。不自动导入任何更新证书、不降低安全策略，不允许证书轮换或测试→正式身份自动切换。
- 下载文件带 Internet Zone 标记，使用正常 ShellExecute 启动已验证的本地 EXE，保留 Windows 的安全检查。静默不等于承诺无 UAC/SmartScreen。

## 安装与结果

复用已安装目录与 Inno 升级/回滚机制，使用 VERYSILENT、SUPPRESSMSGBOXES、NORESTART、NOCLOSEAPPLICATIONS、NOFORCECLOSEAPPLICATIONS，单独保存安装日志。传参使用 .NET ArgumentList，不经过 cmd.exe/PowerShell，不接受 Release 提供命令行。

安装前重新验证原安装身份；安装后不仅看退出码，还验证新版产品状态、收据、用户、Package 外部位置和 COM/菜单注册。安装失败明确报告，不声称必然完全回滚。下载缓存只清理本次创建的精确文件；不确定安装进程状态时保留文件和日志。用户配置不会由更新器删除。

更新状态存放于当前用户 `%LOCALAPPDATA%\SmartZip\UpdateCheck`，仅包含检查时间、跳过版本、协调锁和本次下载；安装和错误日志保留在用户临时目录。不触碰原 SmartZip/7-Zip/WinRAR。

## 验证边界

更新器隔离测试使用内存 HTTP 响应，没有拉取/执行远程安装器，没有修改 GitHub Release、Package 或信任库。覆盖正常和异常元信息、重定向、长度/哈希、取消、真实 Windows 验签及篡改拒绝、C++/.NET 共享/独占锁和实际 ShellExecute Unicode 参数回显。

本机手动启动安装包完成健康 0.1.0.8 → 0.1.0.11 升级，不能替代完整更新弹窗及 GitHub 下载到安装的真实签名更新链验收。当前 0.1.0.11 仍为开发测试签名；本次只准备发布草稿，不触发更新。正式代码签名、公开正式 Release 和 WinGet 的条件见 [发布说明](RELEASE.md)。

可复跑：`pwsh -File build.ps1 -Signing Test -Version 0.1.0.11`。完整构建会重新生成产物；要保留既有验收包时，只运行测试项目。

依据：[GitHub Releases API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)、[WinVerifyTrust](https://learn.microsoft.com/en-us/windows/win32/api/wintrust/nf-wintrust-winverifytrust)、[TaskDialogIndirect](https://learn.microsoft.com/en-us/windows/win32/api/commctrl/nf-commctrl-taskdialogindirect)、[Inno 静默参数](https://jrsoftware.org/ishelp/topic_setupcmdline.htm)。
