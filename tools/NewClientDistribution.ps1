param([Parameter(Mandatory)][string]$ClientFolder,[version]$Version='1.52.0.1700',[string]$OutputDirectory=(Join-Path $PSScriptRoot '../dist'),[long]$PartSize=1GB)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../launcher/UpdateCore.ps1')
if($PartSize -lt 1MB -or $PartSize -ge 2GB){throw 'Part size must be between 1 MiB and 2 GiB.'}
$source=[IO.Path]::GetFullPath($ClientFolder);$out=[IO.Path]::GetFullPath($OutputDirectory)
if($out.StartsWith($source.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output must be outside the client folder.'}
New-Item -ItemType Directory $out -Force|Out-Null
$archive=Join-Path $out "client-full-$Version.zip";$files=@()
$zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
try{
 foreach($item in Get-ChildItem -LiteralPath $source -Recurse -File){
  $relative=[IO.Path]::GetRelativePath($source,$item.FullName).Replace('\','/')
  if($relative -match '(?i)(^|/)(Saved|SaveGames|Logs|Screenshots|\.mh[^/]*)(/|$)|\.(log|db)$'){continue}
  $null=Get-SafePath $source $relative
  $path='Client/'+$relative
  Write-Output "Packaging $relative"
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$item.FullName,$path,[IO.Compression.CompressionLevel]::Optimal)|Out-Null
  $files+=@{path=$path;size=$item.Length;sha256=(Get-FileHash $item.FullName).Hash.ToLowerInvariant()}
 }
}finally{$zip.Dispose()}
if(-not($files|Where-Object path -Match '/Win64/MarvelHeroesOmega.exe$')){throw 'The selected folder does not contain the Win64 game client.'}
$hash=(Get-FileHash $archive).Hash.ToLowerInvariant();$parts=@();$inputFile=[IO.File]::OpenRead($archive);$buffer=[byte[]]::new(1MB)
try{
 $index=0
 while($inputFile.Position -lt $inputFile.Length){
  $index++;$name=('client-full-{0}.zip.part{1:D3}' -f $Version,$index);$path=Join-Path $out $name;$output=[IO.File]::Create($path);$written=0L
  try{while($written -lt $PartSize -and ($read=$inputFile.Read($buffer,0,[int][math]::Min($buffer.Length,$PartSize-$written))) -gt 0){$output.Write($buffer,0,$read);$written+=$read}}finally{$output.Dispose()}
  $parts+=@{asset=$name;size=(Get-Item $path).Length;sha256=(Get-FileHash $path).Hash.ToLowerInvariant()}
 }
}finally{$inputFile.Dispose()}
@{component='client-full';version="$Version";sha256=$hash;parts=$parts;files=$files}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $out "client-full-$Version.package.json")
Write-Output "Full client prepared as $($parts.Count) parts. Upload the .part files and .package.json to the client-patches prerelease. Do not upload the unsplit ZIP."
