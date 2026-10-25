param([ValidateSet('Check','Update','InstallGame')][string]$Action='Check',[string]$TargetRoot=$PSScriptRoot,[switch]$HostUI,[int]$ParentProcessId=0,[switch]$ValidateHost)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'UpdateCore.ps1')
. (Join-Path $PSScriptRoot 'Transfer.ps1')
$root=[IO.Path]::GetFullPath($TargetRoot);$script:ProgressRoot=$root;$updates=Get-SafePath $root '.updates';[IO.Directory]::CreateDirectory($updates)|Out-Null
if($HostUI){
 Add-Type -AssemblyName PresentationFramework
 [xml]$markup='<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Marvel Heroes Update" Width="650" Height="310" WindowStartupLocation="CenterScreen" Background="#000000" Foreground="#E8C979" ResizeMode="NoResize"><StackPanel Margin="32"><TextBlock Text="UPDATING MARVEL HEROES" FontSize="23" FontWeight="Bold"/><TextBlock Name="Status" Text="Closing launcher before installing..." Foreground="White" TextWrapping="Wrap" Margin="0,24,0,16"/><ProgressBar Name="Progress" Height="12" Foreground="#D4AF37" Background="#161616" IsIndeterminate="True"/><TextBlock Name="Detail" Text="The launcher will reopen when the update finishes." Foreground="#AAAAAA" Margin="0,14,0,14" TextWrapping="Wrap"/><Button Name="Reopen" Content="Reopen launcher" Visibility="Collapsed" Height="32"/></StackPanel></Window>'
 $hostWindow=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup))
 $status=$hostWindow.FindName('Status');$progress=$hostWindow.FindName('Progress');$detail=$hostWindow.FindName('Detail');$reopen=$hostWindow.FindName('Reopen')
 $hostState=@{process=$null;finished=$false};$workerScript=$PSCommandPath;$shell=(Get-Process -Id $PID).Path;$waiting=[Diagnostics.Stopwatch]::StartNew()
 $reopen.Add_Click({Start-Process $shell -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'Play.ps1')) -WindowStyle Hidden;$hostWindow.Close()})
 $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(250)
 $timer.Add_Tick({
  try{
   if(-not $hostState.process){
    if($ParentProcessId -and (Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue)){if($waiting.Elapsed.TotalSeconds -gt 30){throw 'The launcher has not closed. Close it, then retry the update.'};return}
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "{0}" -TargetRoot "{1}" -Action {2}' -f $workerScript,$root,$Action
    $hostState.process=Start-Process $shell -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput (Join-Path $updates 'result.txt') -RedirectStandardError (Join-Path $updates 'error.txt') -PassThru
   }
   if(-not $hostState.process.HasExited){
    try{$p=Read-SharedText (Join-Path $updates 'progress.json')|ConvertFrom-Json;$status.Text=$p.message;$progress.IsIndeterminate=$p.percent -lt 0;if($p.percent -ge 0){$progress.Value=$p.percent;$detail.Text=('{0}% — {1:N1} MB / {2:N1} MB' -f $p.percent,($p.done/1MB),($p.total/1MB))}}catch{}
    return
   }
   $timer.Stop();$hostState.finished=$true
   if($hostState.process.ExitCode -in @(0,10)){Start-Process $shell -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'Play.ps1')) -WindowStyle Hidden;$hostWindow.Close();return}
   $failure=Get-Content (Join-Path $updates 'result.txt') -Tail 1
   if(-not $failure){$failure='Update could not complete. Please retry.'};throw $failure
  }catch{$timer.Stop();$hostState.finished=$true;$status.Text=$_.Exception.Message;$progress.IsIndeterminate=$false;$detail.Text='Update incomplete. Reopen the launcher to retry. Play remains locked until updates are complete.';$reopen.Visibility='Visible'}
 })
 $hostWindow.Add_Closing({param($sender,$eventArgs) if(-not $hostState.finished -and $hostState.process -and -not $hostState.process.HasExited){$eventArgs.Cancel=$true}})
 $hostWindow.Add_Closed({$timer.Stop()})
 if($ValidateHost){$hostWindow.Measure([Windows.Size]::new(650,310));$hostWindow.Arrange([Windows.Rect]::new(0,0,650,310));Write-Output 'Updater window validated.';exit 0}
 $timer.Start();$null=$hostWindow.ShowDialog();exit 0
}
$lock=$null;$gameLock=$null;$recoveryComplete=$false
try {
 $lock=[IO.File]::Open((Join-Path $updates 'update.lock'),'OpenOrCreate','ReadWrite','None')
 $settings=Get-Content (Join-Path $root 'LauncherSettings.json') -Raw|ConvertFrom-Json
 $gamePath=if($settings.PSObject.Properties['ClientPath'] -and $settings.ClientPath){[IO.Path]::GetFullPath($settings.ClientPath)}else{Join-Path $root 'Client'}
 if($gamePath.TrimEnd('\') -eq [IO.Path]::GetPathRoot($gamePath).TrimEnd('\') -or $gamePath.TrimEnd('\') -eq $root.TrimEnd('\')){throw 'Choose a dedicated game folder.'}
 $gameStatePath=Join-Path $gamePath '.mh-client-version.json'
 $gameState=if(Test-Path -LiteralPath $gameStatePath){Get-Content -LiteralPath $gameStatePath -Raw|ConvertFrom-Json}else{[pscustomobject]@{version='1.52.0.1700'}}
 $gameInstalled=$false
 if(Test-Path -LiteralPath $gamePath){$gameInstalled=$null -ne (Get-ChildItem -LiteralPath $gamePath -Filter MarvelHeroesOmega.exe -Recurse -File|Where-Object {$_.FullName -match '\\Win64\\' -and $_.FullName -notmatch '\\.mh-updates\\'}|Select-Object -First 1)}
 foreach($directory in Get-ChildItem -LiteralPath $updates -Directory -Filter 'transaction-*'){Restore-Update $root $directory.FullName}
 $gameUpdates=Join-Path $gamePath '.mh-updates'
 if(Test-Path -LiteralPath $gameUpdates){
  $null=Get-SafePath $gamePath '.mh-updates'
  $gameLock=[IO.File]::Open((Join-Path $gameUpdates 'update.lock'),'OpenOrCreate','ReadWrite','None')
  foreach($directory in Get-ChildItem -LiteralPath $gameUpdates -Directory -Filter 'transaction-*'){Restore-Update $gamePath $directory.FullName}
 }
 $recoveryComplete=$true
 $config=Get-Content (Join-Path $root 'UpdateConfig.json') -Raw|ConvertFrom-Json
 if($config.repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'){throw 'The update repository has not been configured.'}
 $repository=[string]$config.repository;$headers=@{'User-Agent'='MarvelHeroesLauncher';Accept='application/vnd.github+json'}
 $release=Invoke-RestMethod "https://api.github.com/repos/$repository/releases/latest" -Headers $headers -TimeoutSec 20
 $asset=@($release.assets|Where-Object name -eq 'update-manifest.json');$prefix="https://github.com/$repository/releases/download/"
 if($asset.Count -ne 1 -or -not $asset[0].browser_download_url.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Release manifest missing or untrusted.'}
 $manifest=Invoke-RestMethod $asset[0].browser_download_url -TimeoutSec 20
 if($manifest.schemaVersion -ne 1){throw 'Unsupported update manifest.'}
 $state=Get-Content (Join-Path $root 'InstalledVersions.json') -Raw|ConvertFrom-Json
 $pending=@();$planned=@{launcher=[string]$state.launcher;client=[string]$gameState.version}
 $full=@($manifest.packages|Where-Object component -eq 'client-full')
 if($Action -eq 'InstallGame'){
  if($gameInstalled){throw 'A game installation already exists in this folder. Use Check for Updates.'}
  if($full.Count -ne 1){throw 'The full game download has not been published yet. Use Locate Game for an existing installation.'}
  $pending+=,$full[0];$planned.client=[string]$full[0].version
 }
 foreach($package in @($manifest.packages)){
  if($package.component -eq 'client-full'){continue}
  if($package.component -notin @('launcher','client')){throw 'Unknown update component.'}
  if($package.component -eq 'client' -and -not $gameInstalled -and $Action -ne 'InstallGame'){continue}
  $current=[version]$planned[$package.component]
  if([version]$package.version -le $current){continue}
  if($package.component -eq 'client' -and [version]$package.fromVersion -ne $current){throw 'Client patch baseline does not match this installation.'}
  $planned[$package.component]=[string]$package.version;$pending+=,$package
 }
 if($Action -eq 'Check'){@{available=($pending.Count -gt 0);fullAvailable=($full.Count -eq 1);gameInstalled=$gameInstalled;summary=(($pending|ForEach-Object {"$($_.component) $($_.version)"}) -join ', ');release=[string]$release.name}|ConvertTo-Json -Compress;exit 0}
 if($pending.Count -eq 0){Write-Output 'Already up to date.';exit 0}
 if(Get-Process MarvelHeroesOmega -ErrorAction SilentlyContinue){throw 'Close the game before updating.'}
 $launcherFiles=@('Play.ps1','StartGame.ps1','CreateAccount.ps1','Update.ps1','UpdateCore.ps1','Transfer.ps1','Launcher.xaml','Play.bat','Launch-Portable.bat','StartClient.bat','StartClientAutoLogin.bat','READ-ME.txt','Assets/avengers-endgame.jpg','Assets/avengers-infinity-war.jpg','Assets/CREDITS.txt')
 $launcherChanged=$false
 foreach($package in $pending){
  $isGame=$package.component -ne 'launcher'
  $destinationRoot=if($isGame){$gamePath}else{$root}
  $cache=if($isGame){$null=Get-SafePath $gamePath '.mh-updates';[IO.Directory]::CreateDirectory($gameUpdates)|Out-Null;$gameUpdates}else{$updates}
  if($isGame -and -not $gameLock){$gameLock=[IO.File]::Open((Join-Path $cache 'update.lock'),'OpenOrCreate','ReadWrite','None')}
  $transaction=Join-Path $cache ('transaction-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($transaction)|Out-Null
  $stage=Join-Path $transaction 'stage';[IO.Directory]::CreateDirectory($stage)|Out-Null
  $allFiles=@();$paths=@{};$totalSize=0L
  if(@($package.files).Count -eq 0){throw 'Empty update package.'}
  foreach($file in $package.files){
   if(-not $isGame -and $file.path -notin $launcherFiles){throw 'Launcher package contains a protected file.'}
   if($isGame -and ($file.path -notlike 'Client/*' -or $file.path -match '(?i)(^|/)(Saved|SaveGames|Logs|Screenshots|\.mh[^/]*)(/|$)|\.(log|db)$')){throw 'Client update contains a protected file.'}
   if($package.component -eq 'client' -and $file.path -match '(?i)(^|/)Config(/|$)|\.ini$'){throw 'Patches cannot replace player configuration.'}
   $null=Get-SafePath $root $file.path
   if($paths.ContainsKey($file.path)){throw 'Duplicate package path.'};$paths[$file.path]=$true
   if([long]$file.size -lt 0){throw 'Invalid file size.'};$totalSize+=[long]$file.size
  }
  $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($destinationRoot))
  if($drive.AvailableFreeSpace -lt ($totalSize*3+100MB)){throw 'Not enough free disk space for download, verification and rollback.'}
  $downloads=Join-Path $cache 'downloads';[IO.Directory]::CreateDirectory($downloads)|Out-Null
  $parts=if($package.PSObject.Properties['parts']){@($package.parts)}else{@([pscustomobject]@{asset=$package.asset;sha256=$package.sha256})}
  $localParts=@()
  foreach($part in $parts){
   if($part.asset -notmatch '^[A-Za-z0-9_.-]+$' -or $part.sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid release asset.'}
   $releaseAsset=@($release.assets|Where-Object name -eq $part.asset)
   if($releaseAsset.Count -ne 1 -or -not $releaseAsset[0].browser_download_url.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Update download missing or untrusted.'}
   $local=Join-Path $downloads ($part.sha256+'.download')
   Receive-Asset $releaseAsset[0].browser_download_url $local $part.sha256;$localParts+=,$local
  }
  $archive=if($localParts.Count -eq 1){$localParts[0]}else{Join-Path $transaction 'package.zip'}
  if($localParts.Count -gt 1){
   Set-TransferStatus 'Assembling game download'
   $output=[IO.File]::Create($archive)
   try{foreach($local in $localParts){$inputFile=[IO.File]::OpenRead($local);try{$inputFile.CopyTo($output)}finally{$inputFile.Dispose()}}}finally{$output.Dispose()}
  }
  Assert-Hash $archive $package.sha256
  Set-TransferStatus 'Verifying and unpacking files'
  Expand-VerifiedPackage $archive $stage $package.files
  foreach($file in $package.files){
   if($isGame){$copy=[pscustomobject]@{path=$file.path.Substring(7);size=$file.size;sha256=$file.sha256;protectLocal=$true;baseSha256=if($file.PSObject.Properties['baseSha256']){$file.baseSha256}else{''}};$allFiles+=,$copy}else{$allFiles+=,$file}
  }
  if($isGame){$stage=Join-Path $stage 'Client';$gameState.version=[string]$package.version;$versionFile='.mh-client-version.json';Write-JsonAtomic $gameState (Join-Path $stage $versionFile)}
  else{$state.launcher=[string]$package.version;$versionFile='InstalledVersions.json';Write-JsonAtomic $state (Join-Path $stage $versionFile);$launcherChanged=$true}
  $allFiles+=,[pscustomobject]@{path=$versionFile;size=(Get-Item (Join-Path $stage $versionFile)).Length;sha256=(Get-FileHash (Join-Path $stage $versionFile)).Hash}
  Set-TransferStatus 'Installing verified files'
  Install-Transaction $destinationRoot $stage $transaction $allFiles
  try {
  # Only remove generated staging inside this exact transaction after commit.
  $stagingRoot=Get-SafePath $transaction 'stage'
  if($stagingRoot.StartsWith([IO.Path]::GetFullPath($transaction).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){
   Remove-Item -LiteralPath $stagingRoot -Recurse -Force
  }
  foreach($local in $localParts){Remove-Item -LiteralPath $local -Force}
  if($localParts.Count -gt 1){Remove-Item -LiteralPath $archive -Force}
  } catch { Write-Output 'Update installed; some temporary files will remain in the cache.' }
 }
 Set-TransferStatus 'Installation complete' 100 100
 Write-Output 'Installation complete.'
 if($launcherChanged){exit 10}else{exit 0}
} catch {Set-TransferStatus $_.Exception.Message;Write-Output $_.Exception.Message;if(-not $recoveryComplete){exit 20}else{exit 1}} finally {if($gameLock){$gameLock.Dispose()};if($lock){$lock.Dispose()}}




