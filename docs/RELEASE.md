# 发布与 WinGet 状态

**发布状态（2026-09-10）：`.15` 开发测试版草稿已创建，尚未公开发布。** 源码已推送到公开仓库；`.15` 草稿固定到源码提交 `8b2616900f9fa6e5d2671527a9b531c1c239b501`。两个附件上传后已核对 GitHub 返回的大小和 SHA-256。仓库首页仍显示“未发布任何版本”，因为草稿不是已发布的发行版。

## 当前测试版材料：0.1.0.15

维护者登录有仓库写入权限的 GitHub 账号后，可[打开 `.15` 草稿](https://github.com/yueyangcode/SmartZip/releases/tag/untagged-167ba3e6cde516e5ee15)查看附件。没有权限的访客无法访问这个草稿；目前没有公开安装包下载链接。GitHub 将“保存草稿”和“公开发布”分为两个操作，见[官方说明](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。

- [测试版说明草稿](../release/NOTES-0.1.0.15.md)与[固定安装包记录](BUILD-0.1.0.15.md)已准备。不得覆盖或重建这个已验收安装包。
- 本地附件在 `build/release/0.1.0.15`：原安装包、`SHA256SUMS.txt`、说明与源码记录；EXE 和校验文件已上传到草稿，版本说明已写入草稿正文。设备日志、恢复资料和私钥未上传。
- 沙盒中的 `Run-Icon-Upgrade.cmd` 已完成一次普通交互升级，记录实际 `C:\SmartZip` 的前后文件清单。脚本没有执行清理、补注册、提权命令或自动重试，不要重复运行。
- 结果在 `C:\SmartZipTestOutput\normal-upgrade-0.1.0.15`。部署检查通过，用户随后确认新图标及 ZIP 解压正常。保留当前 `.15` 安装，不再卸载或重跑 `.14` 全部 case。
- `.15` 源码提交为 [`8b26169`](https://github.com/yueyangcode/SmartZip/commit/8b2616900f9fa6e5d2671527a9b531c1c239b501)，草稿目标标签为 `v0.1.0.15-test`，Git 标签尚未创建。后续 README 翻译和文档提交不改变该草稿的源码目标，也不替换已验收安装包。
- 当前状态为 `draft=true`、`prerelease=true`、`published_at=null`。公开发布仍需用户另行确认；不标为稳定版，不触发当前更新器，不提交公共 WinGet，仓库保持公开。

## 已准备

- 0.1.0.11 源码、测试记录及版本说明；本机健康旧版升级已由日志确认，用户另反馈本机卸载重装、第二台 Windows 11 验证通过，见 [验收记录](TESTED-BASELINE.md)。
- 同目录覆盖升级、版本目录隔离、备份/失败恢复、确认后下载与验签更新，以及对应自动化测试。
- 测试版和正式版构建通道分离；正式版不会导入测试信任或包含提权证书助手。
- `release/Publish-Draft.ps1` 只创建 GitHub 开发版草稿，不公开发布，不设为 latest。
- `release/New-WinGetManifest.ps1` 仅接受版本匹配、系统信任有效且非自签名的正式 EXE；测试版会被拒绝。

## 仍需完成的验收/外部条件

1. GitHub 提示到静默安装的端到端更新验收，以及普通启用 UAC 的新用户环境验证。`.14` 沙盒回滚和正常卸载快照已有结果，不列为待重测。第二台 Windows 11 的旧版本已有用户通过反馈，但不能替代当前 `.15` 的该项环境验证；重装采集范围限制见 [沙盒验收](SANDBOX-0.1.0.14-ACCEPTANCE.md)。
2. 提供正式签名证书。现有测试证书不能代表公开发行信任；不购买证书、不自动修改安全策略或导入 Root。
3. 可信签名后的首次非交互安装、升级和卸载测试。
4. 发布正式 GitHub Release，再校验公开下载文件的哈希并提交公共 WinGet 清单；审核通过才能从公共源安装。

## 构建

新图标版本的源码构建命令为 `pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.15`。当前已有固定哈希产物，不要用该命令重新覆盖已验收安装包或保留作证据的旧包。

正式版需要通过安全的环境注入 `SMARTZIP_SIGN_PFX`、`SMARTZIP_SIGN_PASSWORD`、`SMARTZIP_PUBLISHER`，再运行 `-Signing Release`。
密码不得写入 Git、命令示例或日志。构建使用临时内存私钥载入，验证证书链与用途，使用 RFC3161 时间戳，最后验证 MSIX/EXE 信任。缺少材料或验证失败即停止。
默认时间戳服务为 `http://timestamp.digicert.com`。可信签名也不能保证全新软件完全没有 SmartScreen 提示。

当前正式构建分支尚未有真实可信证书完成端到端构建/安装验证。测试证书到正式证书的迁移不属于本版自动升级范围，需要先卸载测试版；正式证书轮换也需单独设计和验收。

## 历史开发版草稿：0.1.0.11

以下保留原草稿流程供追溯，不应重新发布 `.11` 或将其设为 latest。当前 `.15` 草稿已使用对应源码提交、版本说明和原哈希安装包创建；不要执行下面的历史 `.11` 示例来更新它。

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
