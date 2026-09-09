param([Parameter(Mandatory)][string]$Installer,[Parameter(Mandatory)][string]$Commit,[string]$Version='0.1.0.9')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
if($Version -notmatch '^\d+\.\d+\.\d+\.\d+$' -or $Commit -notmatch '^[0-9a-f]{40}$'){throw 'Exact version and commit SHA are required.'}
$file=Get-Item -LiteralPath $Installer
if($file.Name -ne "SmartZipSetup-$Version-test.exe" -or $file.VersionInfo.ProductVersion.Trim() -ne $Version){throw 'This command creates development draft releases only, with an exact product version.'}
$hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
$out=Join-Path $root "build\release\$Version"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$hashFile=Join-Path $out 'SHA256SUMS.txt'
[IO.File]::WriteAllText($hashFile,"$hash  $($file.Name)`n",[Text.UTF8Encoding]::new($false))
# Credential stays in memory, never in source, git remote URLs, output or files.
$credentialLines="protocol=https`nhost=github.com`n`n" | git -c credential.helper= -c credential.helper=manager credential fill
if($LASTEXITCODE -ne 0){throw 'GitHub credential lookup failed.'}
$credential=@{}
foreach($line in $credentialLines){$parts=$line -split '=',2;if($parts.Count -eq 2){$credential[$parts[0]]=$parts[1]}}
if(!$credential.password){throw 'No GitHub credential available.'}
$headers=@{Authorization="Bearer $($credential.password)";'User-Agent'='SmartZip-release';Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'}
try{
    $api='https://api.github.com/repos/yueyangcode/SmartZip'
    $tag="v$Version-test"
    $existing=@((Invoke-RestMethod "$api/releases?per_page=100" -Headers $headers) | Where-Object tag_name -eq $tag)
    if(@($existing).Count -gt 1 -or ($existing -and !$existing.draft)){throw 'Refusing to change an existing published release.'}
    $notes=[IO.File]::ReadAllText((Join-Path $PSScriptRoot "NOTES-$Version.md"))
    $body=@{tag_name=$tag;target_commitish=$Commit;name="SmartZip $Version 升级开发测试版";body=$notes;draft=$true;prerelease=$true;make_latest='false'}|ConvertTo-Json
    $release=if($existing){Invoke-RestMethod "$api/releases/$($existing.id)" -Headers $headers -Method Patch -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))}else{Invoke-RestMethod "$api/releases" -Headers $headers -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))}
    foreach($asset in @($file,(Get-Item -LiteralPath $hashFile))){
        $digest='sha256:'+(Get-FileHash -LiteralPath $asset.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $existingAsset=@($release.assets | Where-Object name -eq $asset.Name)
        if($existingAsset.Count){
            if($existingAsset.Count -ne 1 -or $existingAsset[0].size -ne $asset.Length -or $existingAsset[0].digest -ne $digest){throw "Draft has a different/unverifiable $($asset.Name); not overwriting it."}
            continue
        }
        $upload="https://uploads.github.com/repos/yueyangcode/SmartZip/releases/$($release.id)/assets?name=$([Uri]::EscapeDataString($asset.Name))"
        $uploaded=Invoke-RestMethod $upload -Method Post -Headers $headers -ContentType 'application/octet-stream' -InFile $asset.FullName
        if($uploaded.size -ne $asset.Length -or $uploaded.digest -ne $digest){throw 'Uploaded asset size/SHA-256 mismatch.'}
    }
    $verified=Invoke-RestMethod "$api/releases/$($release.id)" -Headers $headers
    if(!$verified.draft -or !$verified.prerelease){throw 'Unexpected release visibility.'}
    $verified | Select-Object id,html_url,tag_name,draft,prerelease,@{Name='Assets';Expression={$_.assets.name}} | Format-List
}finally{$headers.Clear();$credential.Clear();$credentialLines=$null}
