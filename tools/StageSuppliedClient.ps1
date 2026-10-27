param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../launcher/UpdateCore.ps1')
$dest=[IO.Path]::GetFullPath($Destination)
if(Test-Path -LiteralPath $dest){throw 'Destination already exists; refusing to overwrite it.'}
$zip=[IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Archive))
try {
 $entry=$zip.GetEntry('CLIENT-FILES.json'); if(-not $entry){throw 'Archive file manifest is missing.'}
 $reader=[IO.StreamReader]::new($entry.Open()); try{$files=@($reader.ReadToEnd() | ConvertFrom-Json)}finally{$reader.Dispose()}
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($f in $files){
  if($f.path -notlike 'Client/*' -or $f.path -match '(?i)(^|/)(Saved|SaveGames|Logs|Screenshots|\.mh[^/]*)(/|$)|\.(log|db)$' -or $f.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or -not $seen.Add([string]$f.path)){throw "Invalid manifest entry: $($f.path)"}
  $e=$zip.GetEntry([string]$f.path); if(-not $e -or $e.Length -ne [long]$f.size){throw "Missing or wrong size: $($f.path)"}
  $null=Get-SafePath $dest $f.path.Substring(7)
 }
 if(-not $seen.Contains('Client/UnrealEngine3/Binaries/Win64/MarvelHeroesOmega.exe')){throw 'Win64 executable is missing.'}
 [IO.Directory]::CreateDirectory($dest)|Out-Null
 $hash=[Security.Cryptography.SHA256]::Create(); $buffer=[byte[]]::new(1048576);$n=0
 foreach($f in $files){
  $target=Get-SafePath $dest $f.path.Substring(7);[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))|Out-Null
  $source=$zip.GetEntry([string]$f.path).Open();$out=[IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try { $hash.Initialize();while(($read=$source.Read($buffer,0,$buffer.Length)) -gt 0){$out.Write($buffer,0,$read);$null=$hash.TransformBlock($buffer,0,$read,$buffer,0)};$null=$hash.TransformFinalBlock($buffer,0,0);if([Convert]::ToHexString($hash.Hash) -ine $f.sha256){throw "Hash mismatch: $($f.path)"} } finally {$out.Dispose();$source.Dispose()}
  $n++;if($n % 500 -eq 0){Write-Output "Verified $n / $($files.Count) files"}
 }
 $files | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ($dest + '.manifest.json') -Encoding utf8
 Write-Output "Verified baseline complete: $n files at $dest"
} finally {$zip.Dispose()}
