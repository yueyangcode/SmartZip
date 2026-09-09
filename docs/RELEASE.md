# 发布与 WinGet 状态

## 已准备

- 0.1.0.11 源码、测试记录及版本说明；本机健康旧版升级已由日志确认，用户另反馈卸载重装通过，见 [验收记录](TESTED-BASELINE.md)。
- 同目录覆盖升级、版本目录隔离、备份/失败恢复、确认后下载与验签更新，以及对应自动化测试。
- 测试版和正式版构建通道分离；正式版不会导入测试信任或包含提权证书助手。
- `release/Publish-Draft.ps1` 只创建 GitHub 开发版草稿，不公开发布，不设为 latest。
- `release/New-WinGetManifest.ps1` 仅接受版本匹配、系统信任有效且非自签名的正式 EXE；测试版会被拒绝。

## 仍需完成的验收/外部条件

1. 0.1.0.11 第二台干净 Windows 11 测试、真实故障回滚和完整卸载快照，以及 GitHub 提示到静默安装的端到端更新验收，见 [升级验收](UPGRADE-TESTS.md)。
2. 提供正式签名证书。现有测试证书不能代表公开发行信任；不购买证书、不自动修改安全策略或导入 Root。
3. 可信签名后的首次非交互安装、升级和卸载测试。
4. 发布正式 GitHub Release，再校验公开下载文件的哈希并提交公共 WinGet 清单；审核通过才能从公共源安装。

## 构建

测试版：`pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.11`。

正式版需要通过安全的环境注入 `SMARTZIP_SIGN_PFX`、`SMARTZIP_SIGN_PASSWORD`、`SMARTZIP_PUBLISHER`，再运行 `-Signing Release`。
密码不得写入 Git、命令示例或日志。构建使用临时内存私钥载入，验证证书链与用途，使用 RFC3161 时间戳，最后验证 MSIX/EXE 信任。缺少材料或验证失败即停止。
默认时间戳服务为 `http://timestamp.digicert.com`。可信签名也不能保证全新软件完全没有 SmartScreen 提示。

当前正式构建分支尚未有真实可信证书完成端到端构建/安装验证。测试证书到正式证书的迁移不属于本版自动升级范围，需要先卸载测试版；正式证书轮换也需单独设计和验收。

## 本次开发版草稿

目标标签为 `v0.1.0.11-test`，状态必须同时为 `draft=true`、`prerelease=true`，不设为 latest。上传已验收的安装包和 `SHA256SUMS.txt`，不上传证书私钥、开发工具、设备日志或恢复备份。草稿对普通访问者不可见；本项目更新器忽略草稿与预发布。

先提交源码并推送，确认远端提交 SHA，再执行现有发布脚本：

```powershell
pwsh -File tests\PublishDraft.Tests.ps1
$releaseCommit = git rev-parse HEAD
pwsh -File release\Publish-Draft.ps1 -Installer dist\SmartZipSetup-0.1.0.11-test.exe -Version 0.1.0.11 -Commit $releaseCommit
```

发布脚本从本机 Git 凭据管理器读取凭据，不将凭据写入文件。它核对产物版本、上传大小及 GitHub 返回的 SHA-256，拒绝覆盖不一致的资产或修改已公开 Release。执行后还应复核标签、目标提交、草稿状态及两个资产。

本次草稿不代表正式发行，不应直接改为正式 Release 来触发更新。正式更新需要下列条件全部满足：可信签名、规范正式资产名、健康安装/升级/卸载验收，以及实际远程更新测试。

## WinGet

预定 ID：`yueyangcode.SmartZip`，仅 Windows x64、per-user、Inno 安装器。

```powershell
pwsh -File release\New-WinGetManifest.ps1 -Installer dist\SmartZipSetup-0.1.0.11-x64.exe -Version 0.1.0.11
winget validate --manifest build\winget\manifests\y\yueyangcode\SmartZip\0.1.0.11
```

以上仅示例正式条件满足后的流程；当前不存在这个正式 x64 产物，也没有可用公共 WinGet 包。非自签名要求是本项目发布生成器的安全限制，不是对所有 WinGet 软件的一概要求。生成器不会提交 PR，也不伪造 InstallerSha256 或已通过静默测试的结果。

依据：[微软 MSIX 签名](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)、[WinGet 提交要求](https://learn.microsoft.com/en-us/windows/package-manager/package/repository)。
