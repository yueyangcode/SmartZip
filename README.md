# SmartZip

Windows 11 原生现代右键菜单中的「智能解压」。内置独立的 7-Zip 后端，无需另装 WinRAR 或 7-Zip，不改变现有压缩软件和旧式菜单。

## 当前状态

- **0.1.0.8**：用户反馈本机及另一台 Windows 11 测试通过，见 [验收记录](docs/TESTED-BASELINE.md)。
- **0.1.0.9**：新增同目录覆盖升级与失败恢复，属于开发测试版。已运行代码层测试，真实覆盖升级、回滚和升级后卸载尚待验收。
- 正式可信签名尚未提供；公共 WinGet 包尚未提交。GitHub 发布准备仅为开发版草稿。

## 使用与安装

支持 Windows 11 x64（Build 22621 或更新版本）。双击 EXE 安装；浏览选择父目录后，向导自动补齐 SmartZip 文件夹并显示最终路径。安装限当前用户可写的本地 NTFS 固定磁盘。

测试版首次安装需同意专用测试证书：仅证书助手请求管理员权限，将公钥加入 LocalMachine\\TrustedPeople，不进入 Root、不导入私钥。软件及 Package 为 per-user。安装前已有的证书不接管；本项目创建的证书按所有权和其他用户使用情况清理。

右键 ZIP、RAR、7Z、CAB、BZ2、GZ、GZIP、TAR 或支持的分卷文件，点击「智能解压」。支持多选及 Unicode/中文、空格、特殊字符路径。普通文件、真实文件夹和压缩包混合普通文件的选择不显示该命令。新版 Context menu 设置页是否存在由 Windows 版本与功能推出状态决定，本软件不会开启 Windows Feature。

开始菜单提供「SmartZip 设置」「检查更新」「卸载 SmartZip」。更新检查每天最多一次，也可手动触发；仅查询本仓库最新正式 Release，确认后打开发布页，不自动下载或执行安装器，不包含 GitHub Token。

## 升级和卸载

0.1.0.9 可对身份完整的 0.1.0.8 或更新版本进行**同目录、同证书**升级，自动使用原安装位置，不需要先卸载。拒绝同版重装、降级、目录迁移及不完整安装，不覆盖无有效产品身份的同名文件夹。

新版写入 Versions 子目录，旧版及用户配置不动。失败恢复先还原旧 Package，再恢复产品状态、卸载文件和快捷方式；恢复被系统拒绝时保留文件/备份并报告失败。旧版本目录保留到正常卸载，暂不自动清除被 Shell 占用的 DLL。断电/强杀恢复不承诺自动完成。

通过正常卸载入口卸载；配置仍保留于原 UserData 目录。不要手动删除安装目录或使用强制清理代替正常卸载。不会删除原版 SmartZip、旧 UnZip 菜单、用户已有的 7-Zip/WinRAR。

升级的真实验收步骤和故障测试边界见 [升级验收](docs/UPGRADE-TESTS.md)。

## 从源码构建

开发机需要 Windows x64、PowerShell 7.4+、.NET SDK 8.0.424，首次构建需联网下载锁定版本及 SHA-256 的依赖。终端用户不需要开发工具。

```powershell
pwsh -File .\\build.ps1 -Signing Test -Version 0.1.0.9
Get-FileHash .\\dist\\SmartZipSetup-0.1.0.9-test.exe -Algorithm SHA256
```

输出单文件安装器；构建不安装软件、Package 或证书。脚本同时运行原生参数、COM 文件筛选、目录页、源生成 JSON、跨进程管道、升级回滚顺序及发布安全门禁测试。模拟/独立 COM 测试不代表 Explorer 或真实安装验收。VS Solution 调用同一构建脚本。

正式构建入口为 `-Signing Release`，要求可信签名材料，没有自签名回退。正式版不包含证书提权助手，也不自动导入证书。签名、GitHub 草稿与 WinGet 清单流程见 [发布说明](docs/RELEASE.md)。测试证书到正式证书的迁移不属于本版自动升级范围。

## 结构与许可证

原生 x64 IExplorerCommand → 同目录 SmartZip.exe → SmartZip AHK 引擎 → 私有 7-Zip 后端。不使用 Contextmenu.exe、Ctrl+C、cmd.exe 或 PATH 查找。

- 本项目及 SmartZip 上游：MIT。
- AutoHotkey：GPL，另含 PCRE 等许可。
- 7-Zip：LGPL/BSD/unRAR 等许可及限制。

许可证、通知和对应上游源码随安装包提供，详见 [ThirdPartyNotices](ThirdPartyNotices.md)。`.private` 私钥、密码文件及本机日志不得提交或分享。

历史故障和早期设计见 [test7 历史说明](docs/TEST7-README-HISTORY.md)，不能用旧测试结果代表新版验收。
