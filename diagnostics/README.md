# test8 安装前检查：只读诊断版

产物：`dist/SmartZip-Preflight-Diagnostic.exe`。这不是 SmartZip 安装包，也不是修复版。

## 用户操作

1. 关闭旧 test8 的报错窗口并取消安装。
2. 从资源管理器双击诊断 EXE，正常运行即可，不要选择“以管理员身份运行”。
3. 按中文向导到“开始诊断”。没有证书授权步骤。
4. 看到“诊断采集已结束”是预期行为。把窗口截图或日志路径提供给开发者。
5. 确认后向导仍会提示诊断已停止，可取消关闭；不会进入真正安装。

日志保存在当前用户临时目录：`SmartZip-Preflight-Diagnostic-<PID>.log`，以及 `SmartZip-Preflight-Inno-<临时目录名>.log`。

## 检查内容

- test8 使用的实际 `LocalApplicationData/Programs/SmartZip Modern` 路径。
- 三次独立采样：`Directory.Exists`、`HKCU/Software/SmartZipModern` 是否存在、`FindPackagesForUser("")` 中精确包名及 Publisher 匹配数。
- 记录三项或条件的结果和触发项，不以磁盘目录作为安装所有权证明。
- 与显式用户 SID 查询、32/64 位注册表视图交叉比较；记录注册表真实句柄名称。
- 记录进程、父进程、自身哈希、限定的路径/运行时环境变量及当前包身份。
- 只记录项目相关注册表值和最多 32 个安装根目录下的名称，不扫描其他文件内容，也不收集凭据。

## 安全边界和局限

诊断工程只链接只读 UserContext，不链接正式 Program、部署事务、TrustBroker、证书或更新检查代码。
唯一持久写入是本地日志；Inno/.NET 运行时另有临时解包缓存。不会写安装目录、导入证书、修改注册表或增删 Package。
Inno PrepareToInstall 在所有路径返回非空字符串，主动停止。无卸载注册、开始菜单、Run、Registry 或删除段。

它复用 test8 的判断表达式、默认目录、AppId、权限设置和 .NET/WinRT 技术栈，但不是 test8 原二进制；独立诊断未复现不等于原故障已修复。
直接运行与由命令行启动的 Inno 包装器，不能替代用户从 Explorer 双击的现场。
`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` 仅供诊断自测，主动停止可返回 Inno 非零退出码（本机为 7），不是软件安装结果。

## 构建

使用本项目已下载的 .NET SDK、Inno 6.2.2、SDK signtool、运行时许可证及已存在的开发签名文件：

```powershell
pwsh -NoProfile -File .\diagnostics\build.ps1
```

构建运行静态无写入保护检查及 8 个原始或条件用例。不导入签名证书，不执行真正安装，不覆盖 test8/test9 安装包。
