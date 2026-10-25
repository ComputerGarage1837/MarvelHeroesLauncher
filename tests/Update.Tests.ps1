$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../launcher/UpdateCore.ps1')
$testRoot=Join-Path $PSScriptRoot ('sandbox-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $testRoot|Out-Null
function Check($condition,$message){if(-not $condition){throw $message};Write-Output "PASS: $message"}
foreach($bad in @('../escape.txt','/absolute','C:/absolute','file:stream','a/../b','CON.txt','trailing.','a\b')){
 $rejected=$false;try{$null=Get-SafePath $testRoot $bad}catch{$rejected=$true};Check $rejected "Reject path $bad"
}
$install=Join-Path $testRoot 'install';$stage=Join-Path $testRoot 'stage';New-Item -ItemType Directory $install,$stage|Out-Null
Set-Content (Join-Path $install 'Play.ps1') 'original';Set-Content (Join-Path $install 'LauncherSettings.json') 'player settings'
Set-Content (Join-Path $stage 'Play.ps1') 'updated';Set-Content (Join-Path $stage 'new.txt') 'new'
$files=@();foreach($name in @('Play.ps1','new.txt')){$p=Join-Path $stage $name;$files+=,[pscustomobject]@{path=$name;sha256=(Get-FileHash $p).Hash;size=(Get-Item $p).Length}}
$transaction=Join-Path $testRoot 'rollback';New-Item -ItemType Directory $transaction|Out-Null
$failed=$false;try{Install-Transaction $install $stage $transaction $files -FailAfter 2}catch{$failed=$true}
Check $failed 'Simulated failed installation is reported'
Check ((Get-Content (Join-Path $install 'Play.ps1')).Trim() -eq 'original') 'Failed installation restores original file'
Check (-not(Test-Path (Join-Path $install 'new.txt'))) 'Rollback removes only its newly installed file'
$transaction=Join-Path $testRoot 'success';New-Item -ItemType Directory $transaction|Out-Null
Install-Transaction $install $stage $transaction $files
Check ((Get-Content (Join-Path $install 'Play.ps1')).Trim() -eq 'updated') 'Successful installation replaces launcher'
Check ((Get-Content (Join-Path $install 'LauncherSettings.json')).Trim() -eq 'player settings') 'Player settings remain unchanged'
$zip=Join-Path $testRoot 'valid.zip';Compress-Archive (Join-Path $stage '*') $zip
$extract=Join-Path $testRoot 'extract';Expand-VerifiedPackage $zip $extract $files
Check (Test-Path (Join-Path $extract 'Play.ps1')) 'Verified archive extracts successfully'
$badFiles=@([pscustomobject]@{path='Play.ps1';sha256=('0'*64);size=$files[0].size},$files[1])
$rejected=$false;try{Expand-VerifiedPackage $zip (Join-Path $testRoot 'bad-hash') $badFiles}catch{$rejected=$true};Check $rejected 'Corrupt file checksum rejected before installation'
$badZip=Join-Path $testRoot 'traversal.zip';$z=[IO.Compression.ZipFile]::Open($badZip,'Create');$e=$z.CreateEntry('../escape.txt');$w=[IO.StreamWriter]::new($e.Open());$w.Write('bad');$w.Dispose();$z.Dispose()
$rejected=$false;try{Expand-VerifiedPackage $badZip (Join-Path $testRoot 'bad-path') $files}catch{$rejected=$true};Check $rejected 'Archive traversal rejected'
$statusPath=Join-Path $testRoot 'progress.json';Write-JsonAtomic @{percent=0} $statusPath
$held=[IO.File]::Open($statusPath,'Open','Read','ReadWrite')
$release=[powershell]::Create();$null=$release.AddScript('param($handle) Start-Sleep -Milliseconds 500; $handle.Dispose()').AddArgument($held);$pendingRelease=$release.BeginInvoke()
try{Write-JsonAtomic @{percent=100} $statusPath;Check ((Read-SharedText $statusPath|ConvertFrom-Json).percent -eq 100) 'Progress replacement retries temporary Windows file locks'}finally{$release.EndInvoke($pendingRelease);$release.Dispose();$held.Dispose()}
Write-Output 'All updater tests passed.'
