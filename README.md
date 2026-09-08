# SmartZip Modern — 本机开发 test6

**仅供开发测试。新版安装器尚未执行，不代表已通过本机或干净机器安装验收。**
产物：`dist\SmartZipModernSetup-test6.exe`，版本 `0.1.0.5`。
旧安装器及 TEST2-REPORT.md、TEST4-INSTALLED-VALIDATION.md 保留作历史证据，不能用它们代表 test6 行为。

## 构建

开发机需要 Windows x64、PowerShell 7.4+、.NET SDK 8.0.424 和首次下载依赖的网络。
LLVM-mingw、Windows SDK 工具和 Inno Setup 6.2.2 使用已锁定 SHA-256 的便携下载。
终端用户不需要这些开发工具。

```powershell
pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.5
Get-FileHash .\dist\SmartZipModernSetup-test6.exe -Algorithm SHA256
```

构建自动运行卸载时序源码回归检查、原生参数、COM 筛选、证书只读校验、故障注入回滚及真实跨进程管道测试，不安装产品或证书。
`SmartZipModern.sln` 的 Makefile 项目调用同一脚本。
额外解压测试：开发机安装 Python 3 后运行 `python .\tests\smoke.py`。
该分支拒绝 Release 构建；公开发行签名不是本阶段范围。
`.private` 中的私钥和 DPAPI 密码文件不能分享，未包含在安装包中。

## 安装结构与权限

- 软件和 Package 均为 per-user，固定目录 `%LOCALAPPDATA%\Programs\SmartZip Modern\Versions\0.1.0.5`。
- 所有部署操作核验进程 SID 与当前会话桌面 Shell 的 SID 一致，拒绝无交互桌面、跨账号及跨会话。事务及卸载状态保存并复核 UserSid。
- UAC 开启时继续拒绝管理员权限运行；仅当 EnableLUA=0 且令牌为 Default（未拆分）时允许同用户管理员进程。配置与令牌不一致时拒绝，不自动修改安全设置。
- `CertificateTrustHelper.exe` 是独立原生 x64 程序，仅该程序使用 `runas` 请求 UAC。
- 唯一证书存储是 `LocalMachine\TrustedPeople`，从不访问 Root 或导入 PFX。
- 当前桌面用户进程负责文件、PackageManager 调用、COM 验证和 HKCU 产品状态；per-user 是归属范围，不等于进程一定没有管理员权限。
- UAC 已关闭的管理员会话中，证书助手仍独立运行，但可能完全没有 UAC 弹窗；这不能证明证书步骤被跳过。安装器不会主动关闭 UAC，也不伪造受限令牌。
- test6 是干净安装/卸载/重装版本；遇到现有安装会停止，不支持覆盖升级。

本机 test2 失败原因是预检查把管理员权限直接等同于错误账号。test3 修正此判断，不代表已经证明 UAC 关闭下的 MSIX/COM 部署成功；真实安装需单独批准。新增 11 个权限策略用例，构建时也会只读核验实际桌面和令牌。

test4 修复 test3 的 `Pipe hasn't been connected yet`：仅在管道连接及对端 PID 验证后创建读写流和启用 AutoFlush。
取消或断连时先关闭管道，再清理流，避免清理时刷新未连接管道掩盖原始异常；重复 Dispose 安全。
`tests/PipeTests` 直接编译生产 TrustBroker.cs，通过真实 Windows 管道及独立子进程验证协议、身份拒绝、断连、取消和句柄释放；不是模拟内存队列。
测试还会先复现旧初始化顺序的异常，以确认回归测试能抓到原缺陷。
可选 `--native-readonly <助手路径>` 仅用于已经处于 UAC-off 管理员会话的开发机，调用校验哈希后的实际助手，发送 OPEN/ROLLBACK；不发送 BEGIN/RELEASE，不更改证书或 Package。
这些测试不替代真实安装、证书导入、MSIX、Settings 和卸载验收。

## 证书助手边界

公钥 DER 内嵌于助手，SHA-256、SHA-1 指纹、Subject、起止有效期和代码签名 EKU 固定在构建中。
助手验证证书自身签名；添加信任必须处于有效期内。清理允许移除已过期但指纹及所有权仍匹配的项目证书。
命令行只接受固定会话格式、随机 nonce 和调用进程 PID；不接受路径、证书文件或任意命令。
通信管道 ACL 限制为原用户与管理员。普通进程核验客户端 PID 与提权进程一致；助手核验管道服务端 PID，从原进程令牌取得用户 SID，
不会把提权账号当成软件安装账号。

原用户进程先校验助手文件的编译期 SHA-256，再请求提权。
提权助手不复制软件、不改 HKCU、不注册 Package、不启动其他程序。
它只操作固定证书及 `HKLM\SOFTWARE\SmartZipModernTestTrust\<固定指纹>` 下的所有权/用户使用记录。

证书安装前存在且没有项目所有权记录：不会接管或删除。
证书由本项目创建：记录创建者和本项目各用户的使用状态。
卸载只有在本次安装确实创建、创建者 SID 匹配、指纹/证书字节匹配且无其他用户使用记录时才删除。
有其他用户使用时保留；这种保守保留不等于清理失败。不要将此开发证书复用于其他软件。

## 部署和回滚

1. Inno `PrepareToInstall` 提取临时 payload，预检干净基线和固定路径。
2. 普通助手创建带本次 nonce 所有权标记的安装目录，复制文件。
3. 建立提权证书会话，添加专用信任或识别已有信任。
4. 原用户调用 `AddPackageByUriAsync`，ExternalLocation 指向本用户版本目录。
5. 验证 Package 身份、Windows PackagedCom 注册、注册后的菜单 manifest，以及实际 IExplorerCommand COM 激活。
6. 全部成功后才让 Inno 创建卸载入口和快捷方式，最后提交 HKCU 产品状态。

第 3–5 步失败：RemovePackageAsync → 同一个仍在运行的提权会话撤销本次新增信任/记录 → 删除带本次标记的安装目录。
不会先留下卸载项和快捷方式再发现 Package 部署失败。
原证书不删除，所有权不明或路径出现重解析点时拒绝危险删除。
Package 注册之后如果正常安装提交阶段再失败，退出钩子会执行补偿清理，包括 Inno 元数据；证书清理可能再次请求 UAC。
若系统拒绝清理或用户取消清理 UAC，必须报告回滚未完成，不能宣称成功或继续删除仍被 Package 引用的文件。

这不是跨进程、证书库和 AppX 的系统级原子事务：断电、强杀、文件被占用以及系统拒绝回滚不能承诺完全无残留。
日志保留在用户临时目录 `SmartZipModern-test6-<PID>.log`，用于确认每次补偿结果。
若清理失败且安装目录仍归本次事务所有，会尽力保留 `recovery.json`；这只是恢复证据，不会自动再次安装或修改系统。

## 正式卸载入口

使用安装器生成的卸载项。test6 不在 InitializeUninstall 或退出事件中执行清理；普通启动先显示 Inno 原生确认框，选择“否”或关闭确认框时不启动部署/证书助手。
确认后才在 `CurUninstallStepChanged(usUninstall)` 建立证书清理提权会话；UAC 被取消则不移除 Package。
原用户移除本项目 Package，助手按所有权决定删除或保留证书，再由 Inno 删除该版本文件、快捷方式和卸载项。
助手启动失败或返回非零时，事件调用 `Abort` 阻止 Inno 继续删除文件、快捷方式和卸载项。后续步骤中途失败可能已改变部分 Package/证书状态，不承诺完全原子回滚；保留日志和卸载入口用于诊断/重试。
`/SILENT`、`/VERYSILENT` 保持 Inno 的既有语义：显式静默卸载不显示启动确认，但仍执行同一清理门控并在失败时中止。
源码回归检查会拒绝旧初始化钩子、缺失阶段判断、忽略助手退出码、缺失 Abort 和异步执行五种退化。它不替代真实点击“否”、取消 UAC 和正常卸载的验收。
此时序依据项目实际使用的 [Inno 6.2.2 源码](https://github.com/jrsoftware/issrc/blob/is-6_2_2/Projects/Uninstall.pas#L620-L655) 和 [Abort 文档](https://jrsoftware.org/ishelp/topic_isxfunc_abort.htm)。
用户解压配置默认保留在 `%LOCALAPPDATA%\SmartZip Modern\UserData`，避免删除密码等个人配置。
不删除既有 SmartZip、旧 UnZip 菜单、现有 7-Zip/WinRAR 或其他 Shell 扩展。

## 解压与许可证

test6 删除了旧设置 GUI 中不可达的右键/发送到注册代码，保留现有记事本编辑独立配置的设置入口。
更正之前的分析：test5 的 Setting 已在旧 GUI 之前 ExitApp，旧注册按钮并非实际可点击；本次是删除死代码以防未来误恢复，不是修复已复现的用户注册表破坏。
保留内置 7-Zip、解压逻辑，以及仍被编码选择对话框使用的提示处理函数。构建会检查解压引擎没有旧注册表/快捷方式写入 API。

原生 `IExplorerCommand` → 同目录 `SmartZip.exe x ...` → AHK SmartZip 源码 → 私有官方 7-Zip 26.03。
不用 Contextmenu.exe、Ctrl+C、cmd.exe 或 PATH 查找，不硬编码个人软件路径。
支持 zip/rar/7z/cab/bz2/gz/gzip/tar、数字分卷、SmartZip 识别的 partN.rar；普通文件、真实文件夹、混合选择隐藏。
SmartZip MIT、AHK GPL、7-Zip LGPL/BSD/unRAR 约束和对应源代码都随包提供。
详见 [ThirdPartyNotices](ThirdPartyNotices.md)。

## 待批准后的验收

- 首次安装：记录 UAC、测试证书许可、Package/COM 和 App extensions 默认状态。
- 故障测试：取消 UAC、使 Package 部署失败、使 COM 验证失败；对比安装前后的文件、注册项和证书。
- 功能：zip/rar/7z/cab/数字分卷；中文、emoji、空格、括号、&、多选；txt/docx/图片/文件夹/混合选择应隐藏。
- 卸载：专用文件、Package、COM、HKCU、快捷方式、卸载项及按所有权可删除的证书；原环境哈希不变。
- 先取消一次卸载：确认框出现前后及选择“否”后，Package/COM/证书/文件/卸载项均应保持不变；之后再正常卸载。UAC 取消测试仅在 UAC 已启用的环境进行，不为测试更改本机 UAC。
- 重装：必须在无上次产品残留的前提下再次成功，最后保留第二次成功安装。
- 稳定性：Explorer/dllhost 崩溃日志、右键延迟、缓存刷新，以及新 Settings 页面是否可管理该扩展。

上述实际安装测试本轮没有执行。独立故障注入测试只证明共享回滚调度逻辑，不替代 Windows 上的端到端验收。

参考：[Inno PrepareToInstall](https://jrsoftware.org/ishelp/topic_scriptevents.htm)、
[MSIX 证书信任排障](https://learn.microsoft.com/en-us/windows/msix/msix-troubleshooting-guide)、
[微软现代菜单扩展](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer)。
