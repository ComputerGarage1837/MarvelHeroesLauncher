$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../launcher/UpdateCore.ps1')
function Check($ok,$message){if(-not $ok){throw $message};Write-Output "PASS: $message"}
$client=[pscustomobject]@{component='client';version='1.0.2';changes=@('Added a costume.','Added artwork.')}
$launcher=[pscustomobject]@{component='launcher';version='1.3.12';changes=@('Added a changelog.')}
$legacy=[pscustomobject]@{component='client';version='1.0.1'}
$pending=Select-UpdateChangelogPackages @($client) @($legacy,$client,$launcher)
$text=Get-UpdateChangelogText $pending
Check ($text -match 'Added a costume' -and $text -notmatch 'Added a changelog') 'Pending notes describe only updates being installed'
$text=Get-UpdateChangelogText (Select-UpdateChangelogPackages @() @($legacy,$client,$launcher))
Check ($text -match 'Added a costume' -and $text -match 'Added a changelog') 'Up-to-date players can see recent game and launcher notes'
Check ((Get-UpdateChangelogText @($legacy)) -match 'No changelog is available for this update') 'Legacy updates do not invent notes'
Check ((Get-UpdateChangelogText @($legacy,$client)) -match 'No changelog is available for this update') 'Missing notes remain visible when other pending updates have notes'
Check ((Get-UpdateChangelogText $null) -eq 'No changelog is available for this update.') 'Empty legacy manifests do not break update checks'
$future=Join-Path $PSScriptRoot ('notes-check-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $future|Out-Null
try{
 $failed=$false
 try{& (Join-Path $PSScriptRoot '../tools/BuildRelease.ps1') -Repository 'Example/Launcher' -Version 9.8.7 -OutputDirectory $future -MetadataOnly}catch{$failed=$true}
 Check $failed 'A new launcher release without version-specific notes is rejected'
}finally{Remove-Item -LiteralPath $future -Recurse -Force}
