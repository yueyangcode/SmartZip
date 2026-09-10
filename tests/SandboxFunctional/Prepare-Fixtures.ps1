$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$inputRoot = Join-Path $repo 'build\sandbox-rollback-0.1.0.14\Input'
$fixtures = Join-Path $inputRoot 'FunctionalFixtures'
$old = Join-Path $repo 'build\tests\installed-ui-20260907-221925'
$sevenZip = Join-Path $repo 'build\payload\Backend\7z.exe'
if ($env:USERNAME -eq 'WDAGUtilityAccount') { throw 'Prepare on the build host, not inside the Sandbox.' }
foreach ($path in @($fixtures, (Join-Path $inputRoot 'Prepare-Functional-Tests.cmd'), (Join-Path $inputRoot 'Collect-Functional-Results.cmd'))) {
    if (Test-Path -LiteralPath $path) { throw "Already exists; preserving earlier materials: $path" }
}
if (!(Test-Path -LiteralPath $sevenZip) -or !(Test-Path -LiteralPath $inputRoot -PathType Container)) { throw 'Existing backend and Sandbox mapping required.' }
if ((Get-FileHash -LiteralPath (Join-Path $repo 'tests\fixtures\rar5-stored.rar.uu')).Hash -ne 'EC73BA623A8E8EEE4909DCDF45F0526FF9ADC1D856D054CE742E6C1BA1FB5FA8') { throw 'RAR source fixture changed.' }
$rar = Join-Path $old '02-RAR\RAR 中文 空格 📦.rar'
if ((Get-FileHash -LiteralPath $rar).Hash -ne '35D75E315D164D2E329AFC28F7D844F013271B4FCFFD4DDD78EFCDD114A383A7') { throw 'Decoded RAR fixture changed.' }
$zip = Join-Path $old '01-ZIP 中文 & (空格)\测试 空格 & % ! ^ (zip) 📦.zip'
$seven = Join-Path $old '03-7Z\测试 空格 & % ! ^ (7z) 📦.7z'
$extra = Join-Path $old '06-Extra'
$payload = Join-Path $old '01-ZIP 中文 & (空格)\内容 📦 & % ! ^.txt'
$payloadHash = (Get-FileHash -LiteralPath $payload).Hash
$rarHash = (Get-FileHash -LiteralPath (Join-Path $old '02-RAR\helloworld.txt')).Hash

# Read only archive stdout. Never launch SmartZip or write extraction output here.
function Check-Archive([string]$Path, [string]$ExpectedHash) {
    $info = [Diagnostics.ProcessStartInfo]::new($sevenZip)
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    foreach ($arg in @('x', '-so', '-bd', '--', $Path)) { $info.ArgumentList.Add($arg) }
    $process = [Diagnostics.Process]::Start($info)
    $errorTask = $process.StandardError.ReadToEndAsync()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [Convert]::ToHexString($sha.ComputeHash($process.StandardOutput.BaseStream)); $process.WaitForExit(); $errors = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or $hash -ne $ExpectedHash) { throw "Archive content check failed: $Path $errors" }
    } finally { $sha.Dispose(); $process.Dispose() }
}
$cases = [Collections.Generic.List[object]]::new()
function Add-Case([string]$Name, [string[]]$Sources, [string[]]$Expected) {
    $directory = Join-Path $fixtures $Name
    New-Item -ItemType Directory -Path $directory | Out-Null
    foreach ($source in $Sources) { [IO.File]::Copy($source, (Join-Path $directory ([IO.Path]::GetFileName($source))), $false) }
    $cases.Add([ordered]@{ Name = $Name; ExpectedPayloadHashes = @($Expected) })
}
foreach ($archive in @($zip, $seven, (Join-Path $extra '单选.cab'), (Join-Path $extra '分卷.7z.001'))) { Check-Archive $archive $payloadHash }
Check-Archive $rar $rarHash
foreach ($extension in @('tar','gz','bz2')) { Check-Archive (Join-Path $extra "测试 空格 & % ! ^ ($extension) 📦.$extension") $payloadHash }
Check-Archive (Join-Path $extra 'GZIP 扩展名测试.gzip') $payloadHash
Add-Case '01-ZIP' @($zip) @($payloadHash)
Add-Case '02-RAR' @($rar) @($rarHash)
Add-Case '03-7Z' @($seven) @($payloadHash)
Add-Case '04-中文 空格 & (括号) 📦' @($zip) @($payloadHash)
Add-Case '05-Multi' @($zip,$rar) @($payloadHash,$rarHash)
Add-Case '06-Filter' @($zip,$payload,(Join-Path $extra 'filter-only.docx'),(Join-Path $extra 'filter-only.jpg')) @()
New-Item -ItemType Directory -Path (Join-Path $fixtures '06-Filter\普通文件夹') | Out-Null
Add-Case '07-CAB' @((Join-Path $extra '单选.cab')) @($payloadHash)
Add-Case '08-TAR' @((Join-Path $extra '测试 空格 & % ! ^ (tar) 📦.tar')) @($payloadHash)
Add-Case '09-GZ' @((Join-Path $extra '测试 空格 & % ! ^ (gz) 📦.gz')) @($payloadHash)
Add-Case '10-BZ2' @((Join-Path $extra '测试 空格 & % ! ^ (bz2) 📦.bz2')) @($payloadHash)
Add-Case '11-GZIP' @((Join-Path $extra 'GZIP 扩展名测试.gzip')) @($payloadHash)
$volumes = @(1..4 | ForEach-Object { Join-Path $extra ('分卷.7z.{0:d3}' -f $_) })
Add-Case '12-Volume-001' $volumes @($payloadHash)
Add-Case '13-Volume-Multi' $volumes @($payloadHash)
# Include only case inputs, never earlier extracted files, logs or product binaries.
$files = @(Get-ChildItem -LiteralPath $fixtures -Recurse -File | ForEach-Object {
    [ordered]@{ Path = [IO.Path]::GetRelativePath($fixtures,$_.FullName); SHA256 = (Get-FileHash -LiteralPath $_.FullName).Hash; Bytes = $_.Length }
})
$directories = @(Get-ChildItem -LiteralPath $fixtures -Recurse -Directory | ForEach-Object { [IO.Path]::GetRelativePath($fixtures,$_.FullName) })
$manifest = [ordered]@{ Version='0.1.0.14'; Source='Existing local smoke fixtures; RAR: pinned libarchive test sample'; Cases=@($cases.ToArray()); Directories=$directories; Files=$files }
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fixtures 'manifest.json') -Encoding utf8BOM
[IO.File]::WriteAllText((Join-Path $fixtures '测试说明.txt'), [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'README.txt')), [Text.UTF8Encoding]::new($true))
Copy-Item -LiteralPath (Join-Path $repo 'tests\fixtures\libarchive-LICENSE.txt') -Destination (Join-Path $fixtures 'libarchive-LICENSE.txt')
foreach ($file in $files) { if ((Get-FileHash -LiteralPath (Join-Path $fixtures $file.Path)).Hash -ne $file.SHA256) { throw 'Copied fixture changed.' } }
if ($cases.Count -ne 13 -or $files.Count -ne 23) { throw "Unexpected fixture count: $($cases.Count) cases / $($files.Count) files" }
foreach ($name in @('Prepare-Functional-Tests.cmd','Collect-Functional-Results.cmd')) { [IO.File]::Copy((Join-Path $PSScriptRoot $name),(Join-Path $inputRoot $name),$false) }
Write-Output "READY: $($cases.Count) cases, $($files.Count) input files. Archive content checks passed; no SmartZip/menu tests executed."
