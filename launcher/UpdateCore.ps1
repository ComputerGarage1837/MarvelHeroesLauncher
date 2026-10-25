Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Get-SafePath([string]$Root,[string]$Relative) {
 if([string]::IsNullOrWhiteSpace($Relative) -or $Relative.Contains('\') -or $Relative -match '[:<>"|?*\x00-\x1f]' -or $Relative.StartsWith('/')){throw 'Unsafe update path.'}
 $parts=$Relative.Split('/')
 foreach($part in $parts){if($part -in @('','.','..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){throw 'Unsafe update path.'}}
 $base=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
 $target=[IO.Path]::GetFullPath([IO.Path]::Combine($base,$Relative))
 if(-not $target.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Update path escapes its destination.'}
 $walk=$base
 foreach($part in @('')+$parts){if($part){$walk=Join-Path $walk $part};if(Test-Path -LiteralPath $walk){if((Get-Item -LiteralPath $walk -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Updates cannot traverse links or junctions.'}}}
 return $target
}
function Move-UpdateFile([string]$Source,[string]$Destination){
 for($attempt=0;$attempt -lt 40;$attempt++){
  try{[IO.File]::Move($Source,$Destination,$true);return}
  catch{if($attempt -eq 39){throw "Could not replace '$Destination'. Close programs using this file and check folder permissions. $($_.Exception.GetBaseException().Message)"};Start-Sleep -Milliseconds 100}
 }
}
function Read-SharedText([string]$Path){
 $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
 $reader=[IO.StreamReader]::new($stream)
 try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
}
function Write-JsonAtomic($Value,[string]$Path){
 $temp=$Path+'.tmp'
 [IO.File]::WriteAllText($temp,($Value|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
 Move-UpdateFile $temp $Path
}
function Assert-Hash([string]$Path,[string]$Expected){
 if($Expected -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected){throw 'Update checksum verification failed.'}
}
function Expand-VerifiedPackage([string]$Archive,[string]$Stage,$Files){
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $expected=@{}; foreach($file in $Files){$null=Get-SafePath $Stage $file.path;if($expected.ContainsKey($file.path)){throw 'Duplicate update file.'};$expected[$file.path]=$file}
 $seen=@{}; $processed=0L; $totalBytes=0L; foreach($item in $Files){$totalBytes+=[long]$item.size}; $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
 try {
  foreach($entry in $zip.Entries){
   if($entry.FullName.EndsWith('/')){continue}
   $destination=Get-SafePath $Stage $entry.FullName
   if(-not $expected.ContainsKey($entry.FullName) -or $seen.ContainsKey($entry.FullName)){throw 'Unexpected or duplicate file in update archive.'}
   $file=$expected[$entry.FullName]
   if($entry.Length -ne [long]$file.size){throw 'Update file size mismatch.'}
   if((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000){throw 'Links are not permitted in updates.'}
   [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))|Out-Null
   [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$destination,$false)
   Assert-Hash $destination $file.sha256
   $seen[$entry.FullName]=$true; $processed+=$entry.Length
   if(Get-Command Set-TransferStatus -ErrorAction SilentlyContinue){Set-TransferStatus "Verifying files ($($seen.Count)/$($expected.Count))" $processed $totalBytes}
  }
  if($seen.Count -ne $expected.Count){throw 'Update archive is incomplete.'}
 } finally {$zip.Dispose()}
}
function Restore-Update([string]$Root,[string]$Transaction){
 $journalPath=Join-Path $Transaction 'journal.json'
 if(-not (Test-Path -LiteralPath $journalPath)){return}
 $journal=Get-Content -LiteralPath $journalPath -Raw|ConvertFrom-Json
 if($journal.status -eq 'complete' -or $journal.status -eq 'rolledback'){return}
 if(Get-Process MarvelHeroesOmega -ErrorAction SilentlyContinue){throw 'Close the game to recover an interrupted update.'}
 foreach($item in @($journal.files)){
  $destination=Get-SafePath $Root $item.path
  if($item.existed){
   $backup=Get-SafePath (Join-Path $Transaction 'backup') $item.path
   Assert-Hash $backup $item.oldHash
   [IO.File]::Copy($backup,$destination,$true)
  } elseif(Test-Path -LiteralPath $destination){Remove-Item -LiteralPath $destination -Force}
 }
 $journal.status='rolledback';Write-JsonAtomic $journal $journalPath
}
function Install-Transaction([string]$Root,[string]$Stage,[string]$Transaction,$Files,[int]$FailAfter=-1){
 if(Get-Process MarvelHeroesOmega -ErrorAction SilentlyContinue){throw 'Close the game before updating.'}
 $journalPath=Join-Path $Transaction 'journal.json';$records=@()
 foreach($file in $Files){
  $destination=Get-SafePath $Root $file.path
  $source=Get-SafePath $Stage $file.path;Assert-Hash $source $file.sha256
  $exists=Test-Path -LiteralPath $destination
  $oldHash=if($exists){(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash}else{''}
  if(($file.path -like 'Client/*' -or ($file.PSObject.Properties['protectLocal'] -and $file.protectLocal)) -and $exists -and (-not $file.PSObject.Properties['baseSha256'] -or -not $file.baseSha256) -and $oldHash -ne $file.sha256){throw 'A new client file conflicts with an existing local file.'}
  if($exists -and $file.PSObject.Properties['baseSha256'] -and $file.baseSha256 -and $oldHash -ne $file.baseSha256 -and $oldHash -ne $file.sha256){throw "Local changes detected in $($file.path). Update cancelled; restore the original file first."}
  if($exists){$backup=Get-SafePath (Join-Path $Transaction 'backup') $file.path;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup))|Out-Null;[IO.File]::Copy($destination,$backup,$false)}
  $records+=@{path=$file.path;existed=$exists;oldHash=$oldHash}
 }
 Write-JsonAtomic @{status='applying';files=$records} $journalPath
 try {
  $count=0
  foreach($file in $Files){
   $destination=Get-SafePath $Root $file.path;$source=Get-SafePath $Stage $file.path
   [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))|Out-Null
   $temp=$destination+'.mh-update-temp';[IO.File]::Copy($source,$temp,$true);Move-UpdateFile $temp $destination
   $count++;if(Get-Command Set-TransferStatus -ErrorAction SilentlyContinue){Set-TransferStatus 'Installing files' $count $Files.Count};if($count -eq $FailAfter){throw 'Simulated interruption'}
  }
  Write-JsonAtomic @{status='complete';files=$records} $journalPath
 } catch {Restore-Update $Root $Transaction;throw}
}




