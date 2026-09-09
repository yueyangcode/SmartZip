$ErrorActionPreference='Stop'
$scriptPath=Join-Path (Split-Path $PSScriptRoot) 'release\Publish-Draft.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Draft publisher syntax error.'}
$assignment=$ast.Find({param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$existing'
},$true)
if(!$assignment){throw 'Draft release selection missing.'}
$selection=[scriptblock]::Create($assignment.Right.Extent.Text)
$tag='v0.1.0.11-test';$api='https://fixture.invalid';$headers=@{}
$old=[pscustomobject]@{id=1;tag_name='v0.1.0.9-test';draft=$true}
$current=[pscustomobject]@{id=2;tag_name=$tag;draft=$true}
# Match Invoke-RestMethod's non-enumerated JSON array without network or credentials.
function Invoke-RestMethod { param($Uri,$Headers) Write-Output -NoEnumerate $fixture }
foreach($case in @(
    @{Items=@();Expected=@()},
    @{Items=@($old);Expected=@()},
    @{Items=@($current);Expected=@(2)},
    @{Items=@($old,$current);Expected=@(2)},
    @{Items=@($old,$current,$current);Expected=@(2,2)}
)){
    $fixture=$case.Items
    $matches=@(& $selection)
    if(($matches.id -join ',') -ne ($case.Expected -join ',')){throw 'Draft selection selected the wrong release(s).'}
}
Write-Output 'PASS actual publisher selection: empty, other version, one match, multiple versions and duplicate matches. No network, credentials or release writes.'
