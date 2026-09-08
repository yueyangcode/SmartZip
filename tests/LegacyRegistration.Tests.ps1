$ErrorActionPreference='Stop'
$source=Get-Content "$PSScriptRoot\..\src\Engine\SmartZip.ahk" -Raw
if($source -match '(?i)\b(RegWrite|RegDeleteKey|RegDelete|FileCreateShortcut|IsContextMenuVisible|IsSendToVisible)\s*\('){throw 'Legacy registration code reintroduced'}
if($source -notmatch 'WM_MOUSEMOVE\(wParam'){throw 'Shared code-page dialog tooltip handler removed'}
if($source -notmatch '(?s)Setting\(\)\s*\{\s*;[^\r\n]+\s*Run\([^\r\n]+\)\s*ExitApp\(\)\s*\}') {throw 'Settings must remain configuration-only'}
Write-Host 'PASS no legacy registry/shortcut writers; config-only settings and shared tooltip handler retained'
