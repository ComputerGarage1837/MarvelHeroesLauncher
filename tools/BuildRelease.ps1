param([Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][version]$Version,[string]$OutputDirectory=(Join-Path $PSScriptRoot '../dist'),[switch]$MetadataOnly)
$ErrorActionPreference='Stop'
if($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'){throw 'Use owner/repository.'}
$source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../launcher'))
$out=[IO.Path]::GetFullPath($OutputDirectory);New-Item -ItemType Directory $out -Force|Out-Null
$stage=Join-Path $out ('build-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $stage|Out-Null
$names=@('Play.ps1','StartGame.ps1','CreateAccount.ps1','Update.ps1','UpdateCore.ps1','Transfer.ps1','Launcher.xaml','Assets/avengers-endgame.jpg','Assets/avengers-infinity-war.jpg','Assets/CREDITS.txt','Play.bat','Launch-Portable.bat','StartClient.bat','StartClientAutoLogin.bat','READ-ME.txt')
$files=@()
foreach($name in $names){$dest=Join-Path $stage $name;New-Item -ItemType Directory ([IO.Path]::GetDirectoryName($dest)) -Force|Out-Null;Copy-Item (Join-Path $source $name) $dest;$item=Get-Item $dest;$files+=@{path=$name;size=$item.Length;sha256=(Get-FileHash $item.FullName).Hash.ToLowerInvariant()}}
$asset="launcher-$Version.zip";$archive=Join-Path $out $asset
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archive -Force
. (Join-Path $source 'UpdateCore.ps1')
[void](Ensure-NativeLauncher $stage)
$packages=@()
if(Test-Path (Join-Path $out 'previous-manifest.json')){
 $previous=Get-Content (Join-Path $out 'previous-manifest.json') -Raw|ConvertFrom-Json
 $packages+=@($previous.packages|Where-Object component -in @('client','client-full'))
 if(-not $MetadataOnly){foreach($package in $packages){$assets=if($package.PSObject.Properties['parts']){@($package.parts.asset)}else{@($package.asset)};foreach($assetName in $assets){if(-not(Test-Path (Join-Path $out $assetName))){throw "Missing retained client asset: $assetName"}}}}
}
foreach($descriptor in Get-ChildItem $out -Filter 'client-*.package.json'){
 $package=Get-Content $descriptor.FullName -Raw|ConvertFrom-Json
 if($package.component -notin @('client','client-full')){throw 'Invalid client descriptor.'}
 if($package.component -eq 'client-full'){$packages=@($packages|Where-Object component -ne 'client-full')}elseif(@($packages|Where-Object {$_.version -eq $package.version -and $_.component -eq 'client'}).Count){continue}
 $packages+=,$package
}
# A newly published full client defines the start of its own patch chain.
# Retired packages from an earlier numbering scheme must not be offered to
# fresh installations, because their fromVersion cannot follow this baseline.
$fullPackages=@($packages|Where-Object component -eq 'client-full')
if($fullPackages.Count -gt 1){throw 'Multiple full client baselines found.'}
if($fullPackages.Count -eq 1){
 $allPatches=@($packages|Where-Object component -eq 'client');$chain=@();$at=[version]$fullPackages[0].version
 while($true){
  $next=@($allPatches|Where-Object {[version]$_.fromVersion -eq $at})
  if($next.Count -gt 1){throw "Ambiguous client patch chain at $at."}
  if($next.Count -eq 0){break}
  if([version]$next[0].version -le $at){throw 'Client patch versions must increase.'}
  $chain+=,$next[0];$at=[version]$next[0].version
 }
 foreach($orphan in $allPatches){
  if($orphan -in $chain){continue}
  if([string]$fullPackages[0].version -eq '1.0.0' -and [string]$orphan.fromVersion -eq '1.52.0.1700' -and [string]$orphan.version -eq '1.52.0.1701'){Write-Warning 'Omitting the retired pre-1.0 client patch.';continue}
  throw "Client patch $($orphan.version) does not follow the current full client baseline."
 }
 $packages=@($packages|Where-Object component -ne 'client')+@($chain)
}
foreach($package in $packages){
 $checkAssets=if($package.PSObject.Properties['parts']){@($package.parts)}else{@([pscustomobject]@{asset=$package.asset;sha256=$package.sha256})}
 foreach($entry in $checkAssets){
  if($entry.asset -notmatch '^[A-Za-z0-9_.-]+$'){throw 'Unsafe client asset name.'}
  if($entry.sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid client asset hash.'}
  if($MetadataOnly){continue}
  $assetPath=Join-Path $out $entry.asset
  if(-not(Test-Path -LiteralPath $assetPath)){throw "Client package is incomplete: $($entry.asset)"}
  if((Get-FileHash -LiteralPath $assetPath).Hash -ne $entry.sha256){throw "Client asset checksum mismatch: $($entry.asset)"}
 }
}
$packages=@($packages|Sort-Object {[version]$_.version})
$packages+=@{component='launcher';version="$Version";asset=$asset;sha256=(Get-FileHash $archive).Hash.ToLowerInvariant();files=$files}
@{schemaVersion=1;packages=$packages}|ConvertTo-Json -Depth 15|Set-Content (Join-Path $out 'update-manifest.json')
@{repository=$Repository}|ConvertTo-Json|Set-Content (Join-Path $stage 'UpdateConfig.json')
@{launcher="$Version";client='0.0.0'}|ConvertTo-Json|Set-Content (Join-Path $stage 'InstalledVersions.json')
@'
@echo off
call "%~dp0Play.bat" -Recover
'@|Set-Content (Join-Path $stage 'Repair-Launcher.bat')
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath (Join-Path $out 'MarvelHeroesLauncher-Install.zip') -Force
Write-Output "Built launcher $Version and update-manifest.json in $out"


