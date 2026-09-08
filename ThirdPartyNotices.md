# Third-party components

This is an independent integration project, not an official Windows, SmartZip,
AutoHotkey or 7-Zip release. No WinRAR binaries are distributed.

## SmartZip

- Upstream: https://github.com/vvyoko/SmartZip
- Revision: d6ff9ea111d735db38fdc5135c93b940224d45ca (SmartZip 3.4, buildVersion 18).
- Copyright (c) 2022 vvyoko; MIT license, retained in Licenses/SmartZip-MIT.txt.
- The original source archive is included as Sources/smartzip.zip.
- The deployed adapted source is Engine/SmartZip.ahk, also in Sources/SmartZip-Modern.ahk.
- Adaptations: installation-relative 7-Zip/icon paths; per-user configuration;
  executable-path quoting; safer unique extraction temporary names; fix the
  uninitialized archive extension lookup; multi-digit RAR part recognition;
  disable the legacy context-menu/settings UI entry; neutral default rename
  rules; optional workspace-only error-reporting support for tests.
- The modern launcher and DLL are separate native components. They pass selected
  file paths explicitly. Contextmenu.exe and its Ctrl+C routine are not included.
- Original icon artwork and donation images are not used by the product. The
  complete unmodified upstream source archive is retained for source provenance.

## AutoHotkey

- Upstream: https://github.com/AutoHotkey/AutoHotkey
- Version: v2.0.19, unmodified official x64 interpreter.
- GPL-2.0 and included PCRE notices: Licenses/AutoHotkey-GPL2-PCRE.txt.
- Corresponding source, build projects and upstream license are included in
  Sources/ahk-source.zip. No proprietary or locally modified compiled AHK binary
  from the original installer is redistributed.
- AutoHotkey runs as a separate executable interpreting the included MIT script.

## 7-Zip

- Upstream: https://github.com/ip7z/7zip / https://www.7-zip.org/
- Version: 26.03, official x64 binaries, unchanged.
- Distributed backend: 7z.exe, 7zG.exe, 7zFM.exe, 7z.dll, help and language files.
- GNU LGPL-2.1-or-later, BSD 2/3-clause code and the unRAR restriction apply as
  described in Licenses/7-Zip.txt and Backend/License.txt.
- Complete corresponding source: Sources/7zip-source.tar.xz. Users may replace
  backend binaries with compatible modified versions; no hash lock prevents it.
- RAR decoding code may not be used to develop a RAR/WinRAR-compatible compressor.
- This package does not install or unregister 7-Zip's own shell extension.

## .NET runtime

DeploymentHelper is self-contained, with .NET runtime 8.0.30 (MIT plus third-party
notices). Windows SDK .NET Ref 10.0.22621.56 includes WinRT.Runtime and the Windows
projection; Licenses/WindowsSDK.rtf and CsWinRT.txt retain applicable Microsoft
SDK terms and C#/WinRT MIT terms. Runtime notices are copied to Licenses during
the build. Source repositories:
https://github.com/dotnet/runtime and https://github.com/microsoft/CsWinRT .

## Build and installer components

- LLVM-mingw 20260826 builds the native files; static runtime notices from its
  distribution are installed in Licenses/NativeRuntime. LLVM/libc++ use the
  Apache-2.0 license with LLVM exceptions; mingw-w64 and compiler runtime notices
  are preserved. Windows supplies UCRT and Win32/COM APIs.
- Inno Setup 6.2.2, copyright Jordan Russell and Martijn Laan. Its license is
  included as Licenses/InnoSetup.txt. The compiler is build-only; its installer
  runtime is part of SmartZipModernSetup.exe. See https://jrsoftware.org/isinfo.php .
- Windows SDK tools are build-only and are not installed on end-user systems.

All original license files and source archives accompany the binary installer;
this document is an index, not a replacement for their full terms.
