# 发布与 WinGet 状态

## 已准备

- 0.1.0.8 已验证源码基线和用户验收记录。
- 0.1.0.9 覆盖升级、版本目录隔离、备份/失败恢复与对应测试。
- 测试版和正式版构建通道分离；正式版不会导入测试信任或包含提权证书助手。
- `release/Publish-Draft.ps1` 只创建 GitHub 开发版草稿，不公开发布，不设为 latest。
- `release/New-WinGetManifest.ps1` 仅接受版本匹配、系统信任有效且非自签名的正式 EXE；测试版会被拒绝。

## 仍需完成的验收/外部条件

1. 0.1.0.9 在 Windows 上的真实覆盖升级、Package 恢复与升级后卸载验收，见 UPGRADE-TESTS.md。
2. 提供正式签名证书。现有测试证书不能代表公开发行信任；不购买证书、不自动修改安全策略或导入 Root。
3. 可信签名后的首次非交互安装、升级和卸载测试。
4. 发布正式 GitHub Release，再校验公开下载文件的哈希并提交公共 WinGet 清单；审核通过才能从公共源安装。

## 构建

测试版：`pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.9`。

正式版需要通过安全的环境注入 `SMARTZIP_SIGN_PFX`、`SMARTZIP_SIGN_PASSWORD`、`SMARTZIP_PUBLISHER`，再运行 `-Signing Release`。
密码不得写入 Git、命令示例或日志。构建使用临时内存私钥载入，验证证书链与用途，使用 RFC3161 时间戳，最后验证 MSIX/EXE 信任。缺少材料或验证失败即停止。
默认时间戳服务为 `http://timestamp.digicert.com`。可信签名也不能保证全新软件完全没有 SmartScreen 提示。

当前正式构建分支尚未有真实可信证书完成端到端构建/安装验证。测试证书到正式证书的迁移不属于本版自动升级范围，需要先卸载测试版；正式证书轮换也需单独设计和验收。

## WinGet

预定 ID：`yueyangcode.SmartZip`，仅 Windows x64、per-user、Inno 安装器。

```powershell
pwsh -File release\New-WinGetManifest.ps1 -Installer dist\SmartZipSetup-0.1.0.9-x64.exe -Version 0.1.0.9
winget validate --manifest build\winget\manifests\y\yueyangcode\SmartZip\0.1.0.9
```

以上是正式条件满足后的流程，不是声称当前已有可用公共 WinGet 包。生成器不会提交 PR，也不伪造 InstallerSha256 或已通过静默测试的结果。

依据：[微软 MSIX 签名](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)、[WinGet 提交要求](https://learn.microsoft.com/en-us/windows/package-manager/package/repository)。
