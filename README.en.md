<p align="center">
  <img src="packaging/Assets/SmartZip.png" width="112" alt="SmartZip logo">
</p>
<h1 align="center">SmartZip</h1>
<p align="center">Extract archives from the Windows 11 modern context menu.</p>
<p align="center">
  <img src="https://img.shields.io/badge/Windows_11-x64-0078D4?style=flat-square" alt="Windows 11 x64">
  <a href="docs/RELEASE.md"><img src="https://img.shields.io/badge/0.1.0.15-draft-F59E0B?style=flat-square" alt="0.1.0.15 development draft"></a>
  <a href="docs/BUILD-0.1.0.15.md"><img src="https://img.shields.io/badge/Installer-14.45_MiB-6366F1?style=flat-square" alt="Installer: 14.45 MiB"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/Source_license-MIT-22C55E?style=flat-square" alt="Project source: MIT license"></a>
</p>
<p align="center">
  <a href="README.md">简体中文</a> · <strong>English</strong> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a>
</p>

## Features

- **Extract from the first-level menu**: select archives and choose **智能解压**, without “Show more options”.
- **Bundled extraction backend**: no separate 7-Zip or WinRAR installation needed; existing archive tools can coexist.
- **Common formats and multiple selections**: ZIP, RAR, 7Z, CAB, TAR, GZ, GZIP, BZ2 and supported numbered volumes, including Chinese characters, spaces and special characters in paths.

## Get started

**`0.1.0.15` is a development draft. No installer is publicly released yet.** The repository therefore shows “No releases published”. [Releases](https://github.com/yueyangcode/SmartZip/releases) · [Release status and checksums](docs/RELEASE.md)

Requires **Windows 11 x64, Build 22621 or later**. Once you have the test installer:

1. Verify its SHA-256 and run `SmartZipSetup-0.1.0.15-test.exe`.
2. Choose a parent directory; setup appends a `SmartZip` folder and installs for the current user.
3. Right-click an archive → **智能解压**. Settings and the normal uninstaller are in the SmartZip Start menu folder.

> **Test certificate:** on first installation, consent allows the certificate helper to request administrator permission and add only a public certificate to `LocalMachine\TrustedPeople`. It does not import a private key or write to the Root certificate store. Uninstall respects certificate ownership; pre-existing certificates are not taken over. Do not disable Windows security protections.

## Updates and limitations

- Healthy older test builds support same-directory, same-certificate upgrades. If registration is incomplete or uninstall fails, keep the logs and report it; do not force-clean.
- No public WinGet package is available. The updater ignores drafts and prereleases, so this test release will not trigger an update prompt.
- The `.15` upgrade has verified deployment logs; the user confirmed the new icons and ZIP extraction. A normal UAC-enabled environment and the remote update flow still need testing. [Acceptance details](docs/SANDBOX-0.1.0.15-ACCEPTANCE.md)
- These README translations do not localize the application. The current installer and menu text are in Simplified Chinese.

## Development and license

Build on Windows with PowerShell 7.4+ and .NET SDK 8.0.425. Main languages: C++, C# and AutoHotkey.

```powershell
pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.15
```

[Build notes](docs/BUILD-0.1.0.15.md) · [Updater design](docs/UPDATER.md) · [Report an issue](https://github.com/yueyangcode/SmartZip/issues)

Project source is licensed under [MIT](LICENSE). Bundled components have their own licenses and source requirements; see [Third-party notices](ThirdPartyNotices.md). This is an independent integration based on [vvyoko/SmartZip](https://github.com/vvyoko/SmartZip).
