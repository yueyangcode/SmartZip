<p align="center">
  <img src="packaging/Assets/SmartZip.png" width="112" alt="SmartZip logo">
</p>
<h1 align="center">SmartZip</h1>
<p align="center">Windows 11 一级右键菜单里的智能解压。</p>
<p align="center">
  <img src="https://img.shields.io/badge/Windows_11-x64-0078D4?style=flat-square" alt="Windows 11 x64">
  <a href="docs/RELEASE.md"><img src="https://img.shields.io/badge/0.1.0.15-draft-F59E0B?style=flat-square" alt="0.1.0.15 development draft"></a>
  <a href="docs/BUILD-0.1.0.15.md"><img src="https://img.shields.io/badge/Installer-14.45_MiB-6366F1?style=flat-square" alt="Installer: 14.45 MiB"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/Source_license-MIT-22C55E?style=flat-square" alt="Project source: MIT license"></a>
</p>
<p align="center">
  <strong>简体中文</strong> · <a href="README.en.md">English</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a>
</p>

## 能做什么

- **右键即解压**：选择压缩包，点击「智能解压」，无需“显示更多选项”。
- **内置解压后端**：无需另装 7-Zip 或 WinRAR，可与已有压缩软件共存。
- **支持常用格式与多选**：ZIP、RAR、7Z、CAB、TAR、GZ、GZIP、BZ2 及支持的数字分卷；支持中文、空格和特殊字符路径。

## 获取与使用

**当前是 `0.1.0.15` 开发测试草稿，尚无公开安装包。** 因此仓库首页会显示“未发布任何版本”。[发行版页面](https://github.com/yueyangcode/SmartZip/releases) · [当前状态与校验值](docs/RELEASE.md)

仅支持 **Windows 11 x64，Build 22621 或更新**。取得测试包后：

1. 核对 SHA-256，运行 `SmartZipSetup-0.1.0.15-test.exe`。
2. 选择父目录，向导会补齐 `SmartZip` 文件夹；软件仅为当前用户安装。
3. 右键压缩包 → **智能解压**。设置与正常卸载入口在开始菜单的 SmartZip 文件夹中。

> **测试证书提示：** 首次安装须同意由证书助手申请管理员权限，将公钥加入 `LocalMachine\TrustedPeople`；不进入 Root、不导入私钥。卸载仅按项目所有权清理，安装前已有的证书不接管。请勿关闭系统安全保护。

## 升级与注意事项

- 健康旧测试版支持同目录、同证书升级；登记不完整或卸载报错时请保留日志并反馈，勿强制清理。
- 目前没有公共 WinGet 包。更新器忽略草稿和 Pre-release，发布测试版不会弹出自动更新提示。
- `.15` 的覆盖升级已有日志核验，新图标和 ZIP 解压获用户确认。普通 UAC 环境及远程自动更新链仍待验证。[验收详情](docs/SANDBOX-0.1.0.15-ACCEPTANCE.md)

## 开发与许可

Windows 构建环境：PowerShell 7.4+、.NET SDK 8.0.425；主要使用 C++、C#、AutoHotkey。

```powershell
pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.15
```

[构建说明](docs/BUILD-0.1.0.15.md) · [更新器设计](docs/UPDATER.md) · [反馈问题](https://github.com/yueyangcode/SmartZip/issues)

本项目源码采用 [MIT](LICENSE)。内置组件另有许可证及源码提供要求，见[第三方声明](ThirdPartyNotices.md)。项目基于 [vvyoko/SmartZip](https://github.com/vvyoko/SmartZip)，是独立集成项目。
