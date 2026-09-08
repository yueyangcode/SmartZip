param()
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
New-Item -ItemType Directory -Force -Path "$root\downloads", "$root\.tools", "$root\vendor" | Out-Null
$items = @(
  @('llvm.zip','https://github.com/mstorsjo/llvm-mingw/releases/download/20260826/llvm-mingw-20260826-ucrt-x86_64.zip'),
  @('inno.zip','https://api.nuget.org/v3-flatcontainer/tools.innosetup/6.2.2/tools.innosetup.6.2.2.nupkg'),
  @('sdk.zip','https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.cpp/10.0.26100.3916/microsoft.windows.sdk.cpp.10.0.26100.3916.nupkg'),
  @('sdk-x64.zip','https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.cpp.x64/10.0.26100.3916/microsoft.windows.sdk.cpp.x64.10.0.26100.3916.nupkg'),
  @('smartzip.zip','https://codeload.github.com/vvyoko/SmartZip/zip/d6ff9ea111d735db38fdc5135c93b940224d45ca'),
  @('ahk.zip','https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.19/AutoHotkey_2.0.19.zip'),
  @('ahk-source.zip','https://codeload.github.com/AutoHotkey/AutoHotkey/zip/refs/tags/v2.0.19'),
  @('7zip.exe','https://github.com/ip7z/7zip/releases/download/26.03/7z2603-x64.exe'),
  @('7zip-source.tar.xz','https://github.com/ip7z/7zip/releases/download/26.03/7z2603-src.tar.xz'),
  @('7zr.exe','https://github.com/ip7z/7zip/releases/download/26.03/7zr.exe')
)
$hashes=Get-Content "$root\dependencies.sha256.json" -Raw | ConvertFrom-Json -AsHashtable
foreach ($item in $items) {
  $dest = Join-Path "$root\downloads" $item[0]
  if (-not (Test-Path -LiteralPath $dest)) {
    Write-Host "Downloading $($item[0])"
    Invoke-WebRequest -Uri $item[1] -OutFile $dest
  }
  $hash=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
  if($hash -ne $hashes[$item[0]]){throw "SHA256 mismatch for $($item[0]). Do not execute this download."}
  Write-Host "$($item[0]) $hash OK"
}
