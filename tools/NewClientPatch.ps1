param([Parameter(Mandatory)][string]$ChangedFiles,[Parameter(Mandatory)][string]$PreviousClient,[Parameter(Mandatory)][version]$FromVersion,[Parameter(Mandatory)][version]$Version,[Parameter(Mandatory)][string[]]$Changes,[string]$OutputDirectory=(Join-Path $PSScriptRoot '../dist'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../launcher/UpdateCore.ps1')
if($Version -le $FromVersion){throw 'Patch version must increase.'}
if(-not @($Changes|Where-Object {-not [string]::IsNullOrWhiteSpace($_)}).Count){throw 'Describe the changes included in this patch.'}
$changed=[IO.Path]::GetFullPath($ChangedFiles);$baseline=[IO.Path]::GetFullPath($PreviousClient)
$out=[IO.Path]::GetFullPath($OutputDirectory);New-Item -ItemType Directory $out -Force|Out-Null
$stage=Join-Path $out ('patch-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory (Join-Path $stage 'Client')|Out-Null
$files=@()
foreach($item in Get-ChildItem $changed -Recurse -File){
 $relative=[IO.Path]::GetRelativePath($changed,$item.FullName).Replace('\','/')
 $path='Client/'+$relative
 if($path -match '(?i)(^|/)(Saved|SaveGames|Logs|Screenshots|Config)(/|$)|\.(ini|log|db)$'){throw "Protected player file: $relative"}
 $target=Get-SafePath $stage $path;$old=Get-SafePath $baseline $relative
 $hash=(Get-FileHash $item.FullName).Hash.ToLowerInvariant();$oldHash=if(Test-Path -LiteralPath $old){(Get-FileHash $old).Hash.ToLowerInvariant()}else{''}
 if($hash -eq $oldHash){continue}
 New-Item -ItemType Directory ([IO.Path]::GetDirectoryName($target)) -Force|Out-Null;Copy-Item -LiteralPath $item.FullName -Destination $target
 $files+=@{path=$path;size=$item.Length;sha256=$hash;baseSha256=$oldHash}
}
if(-not $files.Count){throw 'No changed files found.'}
$asset="client-$Version.zip";$archive=Join-Path $out $asset
Compress-Archive -Path (Join-Path $stage 'Client') -DestinationPath $archive -Force
if((Get-Item $archive).Length -ge 2GB){throw 'Client patch exceeds the GitHub release asset size limit. Split it into sequential smaller patches.'}
@{component='client';version="$Version";fromVersion="$FromVersion";asset=$asset;sha256=(Get-FileHash $archive).Hash.ToLowerInvariant();files=$files;changes=@($Changes|ForEach-Object {$_.Trim()})}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $out "client-$Version.package.json")
Write-Output "Created $asset. Upload it and its package.json descriptor to the client-patches release before publishing the next launcher release."
