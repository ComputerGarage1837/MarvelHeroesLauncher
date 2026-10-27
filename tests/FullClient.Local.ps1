param([Parameter(Mandatory)][string]$PackageDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../launcher/UpdateCore.ps1')
$packageRoot=[IO.Path]::GetFullPath($PackageDirectory)
$package=Get-Content (Join-Path $packageRoot 'client-full-1.0.0.package.json') -Raw|ConvertFrom-Json
$sandbox=Join-Path $env:TEMP ('mh-full-install-test-'+[guid]::NewGuid().ToString('N'))
$launcher=Join-Path $sandbox 'launcher';$game=Join-Path $sandbox 'game';$downloads=Join-Path $game '.mh-updates/downloads'
New-Item -ItemType Directory $launcher,$downloads -Force|Out-Null
foreach($name in @('Update.ps1','UpdateCore.ps1','Transfer.ps1')){Copy-Item (Join-Path $PSScriptRoot "../launcher/$name") $launcher}
Set-Content (Join-Path $launcher 'UpdateConfig.json') '{"repository":"Test/Test"}'
Set-Content (Join-Path $launcher 'InstalledVersions.json') '{"launcher":"1.0.0","client":"0.0.0"}'
$settings=Get-PlayerSettings $launcher;$settings.ClientPath=$game;Save-PlayerSettings $launcher $settings
foreach($part in $package.parts){$source=Join-Path $packageRoot $part.asset;$target=Join-Path $downloads ($part.sha256+'.download');New-Item -ItemType HardLink -Path $target -Target $source|Out-Null}
$manifest=Join-Path $sandbox 'manifest.json';@{schemaVersion=1;packages=@($package)}|ConvertTo-Json -Depth 20|Set-Content $manifest
$runner=@'
function Invoke-RestMethod {
 param($Uri,$Headers,$TimeoutSec)
 $manifest=Get-Content -LiteralPath $env:MH_FULL_MANIFEST -Raw|ConvertFrom-Json
 if($Uri -like 'https://api.github.com/*'){
  $assets=@(@{name='update-manifest.json';browser_download_url='https://github.com/Test/Test/releases/download/test/update-manifest.json'})
  foreach($part in $manifest.packages[0].parts){$assets+=@{name=$part.asset;browser_download_url=('https://github.com/Test/Test/releases/download/test/'+$part.asset)}}
  return @{name='test';assets=$assets}
 }
 return $manifest
}
& (Join-Path $env:MH_FULL_LAUNCHER 'Update.ps1') -TargetRoot $env:MH_FULL_LAUNCHER -Action InstallGame
'@
$runnerPath=Join-Path $sandbox 'runner.ps1';Set-Content $runnerPath $runner
$env:MH_FULL_MANIFEST=$manifest;$env:MH_FULL_LAUNCHER=$launcher
& (Get-Process -Id $PID).Path -NoProfile -File $runnerPath
if($LASTEXITCODE -ne 0){throw "Full clean-install test failed. Files are at $sandbox"}
if(-not(Test-Path -LiteralPath (Join-Path $game 'UnrealEngine3/Binaries/Win64/MarvelHeroesOmega.exe'))){throw 'Installed executable missing.'}
if((Get-Content (Join-Path $game '.mh-client-version.json') -Raw|ConvertFrom-Json).version -ne '1.0.0'){throw 'Installed version is incorrect.'}
Write-Output "Full installer successfully installed and verified client 1.0.0 at $sandbox"
