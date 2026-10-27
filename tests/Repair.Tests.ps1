$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../launcher/UpdateCore.ps1')
$sandbox=Join-Path $PSScriptRoot ('sandbox-repair-'+[guid]::NewGuid().ToString('N'))
$launcher=Join-Path $sandbox 'launcher';$game=Join-Path $sandbox 'game';$payload=Join-Path $sandbox 'payload/Client'
New-Item -ItemType Directory $launcher,$game,$payload -Force|Out-Null
foreach($name in @('Update.ps1','UpdateCore.ps1','Transfer.ps1')){Copy-Item (Join-Path $PSScriptRoot "../launcher/$name") $launcher}
Set-Content (Join-Path $launcher 'UpdateConfig.json') '{"repository":"Test/Test"}'
Set-Content (Join-Path $launcher 'InstalledVersions.json') '{"launcher":"1.0.0","client":"0.0.0"}'
$expected=@{'UnrealEngine3/Binaries/Win64/MarvelHeroesOmega.exe'='binary';'Data/test.bin'='correct';'Data/missing.bin'='restored';'Config/settings.ini'='default'}
$files=@();foreach($key in $expected.Keys){$p=Join-Path $payload $key;New-Item -ItemType Directory ([IO.Path]::GetDirectoryName($p)) -Force|Out-Null;[IO.File]::WriteAllText($p,$expected[$key]);$files+=@{path=('Client/'+$key);size=(Get-Item $p).Length;sha256=(Get-FileHash $p).Hash.ToLowerInvariant()}}
$archive=Join-Path $sandbox 'client.zip';Compress-Archive (Join-Path $sandbox 'payload/Client') $archive
foreach($key in @('UnrealEngine3/Binaries/Win64/MarvelHeroesOmega.exe','Data/test.bin','Config/settings.ini')){$p=Join-Path $game $key;New-Item -ItemType Directory ([IO.Path]::GetDirectoryName($p)) -Force|Out-Null;[IO.File]::WriteAllText($p, $(if($key -eq 'Data/test.bin'){'broken'}elseif($key -eq 'Config/settings.ini'){'personal'}else{$expected[$key]}))}
$settings=Get-PlayerSettings $launcher;$settings.ClientPath=$game;Save-PlayerSettings $launcher $settings
$digest=(Get-FileHash $archive).Hash.ToLowerInvariant();@{schemaVersion=1;packages=@(@{component='client-full';version='1.0.0';asset='client.zip';sha256=$digest;files=$files})}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $sandbox 'manifest.json')
Add-Content (Join-Path $launcher 'Transfer.ps1') "`nfunction Receive-Asset([string]`$Url,[string]`$Path,[string]`$Hash){Copy-Item -LiteralPath `$env:MH_TEST_ARCHIVE -Destination `$Path -Force;Assert-Hash `$Path `$Hash}"
$runner=@'
function Invoke-RestMethod {
 param($Uri,$Headers,$TimeoutSec)
 if($Uri -like 'https://api.github.com/*'){return @{name='test';assets=@(@{name='update-manifest.json';browser_download_url='https://github.com/Test/Test/releases/download/test/update-manifest.json'},@{name='client.zip';browser_download_url='https://github.com/Test/Test/releases/download/test/client.zip'},@{name='patch.zip';browser_download_url='https://github.com/Test/Test/releases/download/test/patch.zip'})}}
 return Get-Content -LiteralPath $env:MH_TEST_MANIFEST -Raw | ConvertFrom-Json
}
& (Join-Path $env:MH_TEST_LAUNCHER 'Update.ps1') -TargetRoot $env:MH_TEST_LAUNCHER -Action $env:MH_TEST_ACTION
'@
$runnerPath=Join-Path $sandbox 'runner.ps1';Set-Content $runnerPath $runner
$env:MH_TEST_ARCHIVE=$archive;$env:MH_TEST_MANIFEST=Join-Path $sandbox 'manifest.json';$env:MH_TEST_LAUNCHER=$launcher;$env:MH_TEST_ACTION='Repair'
& (Get-Process -Id $PID).Path -NoProfile -File $runnerPath
if($LASTEXITCODE -ne 0){throw 'Repair failed.'}
if([IO.File]::ReadAllText((Join-Path $game 'Data/test.bin')) -ne 'correct'){throw 'Changed file was not repaired.'}
if([IO.File]::ReadAllText((Join-Path $game 'Data/missing.bin')) -ne 'restored'){throw 'Missing file was not restored.'}
if([IO.File]::ReadAllText((Join-Path $game 'Config/settings.ini')) -ne 'personal'){throw 'Personal settings were not preserved.'}
if((Get-Content (Join-Path $game '.mh-client-version.json') -Raw|ConvertFrom-Json).version -ne '1.0.0'){throw 'Baseline version was not recorded.'}
Write-Output 'Repair restores changed and missing files, preserves settings, and records the baseline.'
# A second run with intact files must not download or overwrite settings.
[IO.File]::WriteAllText((Join-Path $launcher 'Transfer.ps1'), ([IO.File]::ReadAllText((Join-Path $launcher 'Transfer.ps1')) + "`nfunction Receive-Asset { throw 'Unexpected download for an intact client.' }`n"))
& (Get-Process -Id $PID).Path -NoProfile -File $runnerPath
if($LASTEXITCODE -ne 0){throw 'An intact client did not pass verification.'}
Write-Output 'An intact client verifies without downloading the full game.'
$patchDir=Join-Path $sandbox 'patch/Client/Data';New-Item -ItemType Directory $patchDir -Force|Out-Null
$patchFile=Join-Path $patchDir 'test.bin';[IO.File]::WriteAllText($patchFile,'updated')
$patchArchive=Join-Path $sandbox 'patch.zip';Compress-Archive (Join-Path $sandbox 'patch/Client') $patchArchive
$manifest=Get-Content (Join-Path $sandbox 'manifest.json') -Raw|ConvertFrom-Json
$old=@($manifest.packages[0].files|Where-Object path -eq 'Client/Data/test.bin')[0]
$patch=@{component='client';version='1.0.1';fromVersion='1.0.0';asset='patch.zip';sha256=(Get-FileHash $patchArchive).Hash.ToLowerInvariant();files=@(@{path='Client/Data/test.bin';size=(Get-Item $patchFile).Length;sha256=(Get-FileHash $patchFile).Hash.ToLowerInvariant();baseSha256=$old.sha256})}
$manifest.packages=@($manifest.packages)+@($patch);$manifest|ConvertTo-Json -Depth 10|Set-Content (Join-Path $sandbox 'manifest.json')
$env:MH_TEST_PATCH=$patchArchive
Add-Content (Join-Path $launcher 'Transfer.ps1') "`nfunction Receive-Asset([string]`$Url,[string]`$Path,[string]`$Hash){if(`$Url.EndsWith('patch.zip')){`$source=`$env:MH_TEST_PATCH}else{`$source=`$env:MH_TEST_ARCHIVE};Copy-Item -LiteralPath `$source -Destination `$Path -Force;Assert-Hash `$Path `$Hash}"
[IO.File]::WriteAllText((Join-Path $game 'Data/test.bin'),'broken again')
& (Get-Process -Id $PID).Path -NoProfile -File $runnerPath
if($LASTEXITCODE -ne 0 -or [IO.File]::ReadAllText((Join-Path $game 'Data/test.bin')) -ne 'updated'){throw 'Repair failed to apply the latest client patch.'}
if((Get-Content (Join-Path $game '.mh-client-version.json') -Raw|ConvertFrom-Json).version -ne '1.0.1'){throw 'Repair did not record the patched version.'}
Write-Output 'Repair restores the latest patched version.'
[IO.File]::WriteAllText((Join-Path $game 'Data/test.bin'),'correct');Set-Content (Join-Path $game '.mh-client-version.json') '{"version":"1.0.0"}'
$env:MH_TEST_ACTION='Update';& (Get-Process -Id $PID).Path -NoProfile -File $runnerPath;$env:MH_TEST_ACTION='Repair'
if($LASTEXITCODE -ne 0 -or [IO.File]::ReadAllText((Join-Path $game 'Data/test.bin')) -ne 'updated'){throw 'Incremental update failed to apply the client patch.'}
Write-Output 'A client at 1.0 receives the incremental 1.0.1 patch.'
$exe='UnrealEngine3/Binaries/Win64/MarvelHeroesOmega.exe';[IO.File]::WriteAllText((Join-Path $game $exe),'custom binary')
@{paths=@($exe)}|ConvertTo-Json|Set-Content (Join-Path $game '.mh-protected-files.json')
& (Get-Process -Id $PID).Path -NoProfile -File $runnerPath
if($LASTEXITCODE -ne 0 -or [IO.File]::ReadAllText((Join-Path $game $exe)) -ne 'custom binary'){throw 'Explicitly protected executable was not preserved.'}
Write-Output 'An explicitly protected executable remains untouched during repair.'
