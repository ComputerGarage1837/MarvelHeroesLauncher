param([switch]$ValidateOnly,[string]$PreviewPath,[switch]$PreviewUpdate,[switch]$PreviewSetup,[switch]$PreviewSettings)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms,System.Drawing
. (Join-Path $PSScriptRoot 'UpdateCore.ps1')
Set-StrictMode -Off
$root=$PSScriptRoot
$choices=@('Automatic (monitor resolution)','1280 x 720  |  16:9','1920 x 1080  |  16:9','2560 x 1440  |  16:9','3840 x 2160  |  16:9','2560 x 1080  |  Ultrawide 21:9','3440 x 1440  |  Ultrawide 21:9','3840 x 1600  |  Ultrawide 21:9','5120 x 2160  |  Ultrawide 21:9','3840 x 1080  |  Super ultrawide 32:9','5120 x 1440  |  Super ultrawide 32:9','7680 x 2160  |  Super ultrawide 32:9')
$saved=Get-PlayerSettings $root
if($saved.Resolution -notin $choices){$choices+=,[string]$saved.Resolution}
function Save-Settings {Save-PlayerSettings $root $saved}
function Open-AccountForm {Start-Process (Get-Process -Id $PID).Path -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'CreateAccount.ps1')) -WindowStyle Hidden}
function New-LauncherShortcut {
 $desktop=[Environment]::GetFolderPath('DesktopDirectory');$shell=New-Object -ComObject WScript.Shell
 $link=$shell.CreateShortcut((Join-Path $desktop 'Marvel Heroes Omega.lnk'))
 $link.TargetPath=(Get-Process -Id $PID).Path;$link.Arguments='-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'Play.ps1');$link.WorkingDirectory=$root;$link.Description='Play Marvel Heroes Omega';$link.Save()
 [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link);[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
}
function Show-FirstTimeSetup {
 $setup=[Windows.Forms.Form]::new();$setup.Text='Welcome to Marvel Heroes';$setup.ClientSize=[Drawing.Size]::new(610,445);$setup.StartPosition='CenterScreen';$setup.FormBorderStyle='FixedDialog';$setup.MaximizeBox=$false;$setup.BackColor=[Drawing.Color]::Black;$setup.ForeColor=[Drawing.Color]::WhiteSmoke;$setup.Font=[Drawing.Font]::new('Segoe UI',11)
 $intro=[Windows.Forms.Label]::new();$intro.Text='GET READY TO ASSEMBLE';$intro.Font=[Drawing.Font]::new('Segoe UI',20,[Drawing.FontStyle]::Bold);$intro.ForeColor=[Drawing.Color]::FromArgb(212,175,98);$intro.SetBounds(24,20,560,40);$setup.Controls.Add($intro)
 $steps=[Windows.Forms.Label]::new();$steps.Text='1. Choose a game folder, or select your existing game installation.';$steps.SetBounds(24,80,560,50);$setup.Controls.Add($steps)
 $location=[Windows.Forms.TextBox]::new();$location.ReadOnly=$true;$location.Text=$saved.ClientPath;$location.SetBounds(24,130,420,30);$setup.Controls.Add($location)
 $browse=[Windows.Forms.Button]::new();$browse.Text='Browse...';$browse.SetBounds(456,127,125,34);$setup.Controls.Add($browse)
 $browse.Add_Click({$picker=[Windows.Forms.FolderBrowserDialog]::new();$picker.Description='Choose your new game folder or locate your existing game';$picker.UseDescriptionForTitle=$true;$picker.SelectedPath=$location.Text;try{if($picker.ShowDialog() -eq 'OK'){$chosen=[IO.Path]::GetFullPath($picker.SelectedPath);if($chosen.TrimEnd('\') -eq [IO.Path]::GetPathRoot($chosen).TrimEnd('\') -or $chosen.TrimEnd('\') -eq $root.TrimEnd('\')){[void][Windows.Forms.MessageBox]::Show('Choose a dedicated game folder.')}else{$location.Text=$chosen}}}finally{$picker.Dispose()}})
 $desktop=[Windows.Forms.CheckBox]::new();$desktop.Text='2. Create a desktop shortcut';$desktop.Checked=$true;$desktop.SetBounds(24,184,560,30);$setup.Controls.Add($desktop)
 $account=[Windows.Forms.Label]::new();$account.Text='3. Create an account, then sign in inside the game with your email and password. Already registered? Use your existing account.';$account.SetBounds(24,232,560,58);$setup.Controls.Add($account)
 $register=[Windows.Forms.Button]::new();$register.Text='Create account';$register.SetBounds(24,300,180,34);$setup.Controls.Add($register);$register.Add_Click({Open-AccountForm})
 $note=[Windows.Forms.Label]::new();$note.Text='Your monitor resolution is detected automatically. You can change display settings from the launcher.';$note.ForeColor=[Drawing.Color]::Silver;$note.SetBounds(24,349,560,48);$setup.Controls.Add($note)
 $finish=[Windows.Forms.Button]::new();$finish.Text='Finish setup';$finish.SetBounds(400,400,180,34);$finish.BackColor=[Drawing.Color]::FromArgb(212,175,98);$finish.ForeColor=[Drawing.Color]::Black;$setup.Controls.Add($finish)
 $finish.Add_Click({try{$saved.ClientPath=$location.Text;if($desktop.Checked){New-LauncherShortcut};$saved.SetupComplete=$true;Save-Settings;$setup.Close()}catch{$note.Text='Setup could not finish: '+$_.Exception.Message}})
 if($ValidateOnly){if($PreviewSetup -and $PreviewPath){Export-FormPreview $setup $PreviewPath};$setup.Dispose();return}
 [void]$setup.ShowDialog();$setup.Dispose();Refresh-Game
}
$launcherLock=$null
if(-not $ValidateOnly){try{$launcherLock=[IO.File]::Open((Join-Path $root '.launcher.lock'),'OpenOrCreate','ReadWrite','None')}catch{[void][System.Windows.MessageBox]::Show('This launcher is already open.','Marvel Heroes');exit 0}}
[xml]$xaml=Get-Content (Join-Path $root 'Launcher.xaml') -Raw
$reader=[Xml.XmlNodeReader]::new($xaml);$window=[Windows.Markup.XamlReader]::Load($reader)
$ui=@{};foreach($name in @('SettingsButton','AccountButton','HeroImage','UpdateSummary','UpdateButton','GameLocation','FolderButton','LocateButton','StatusText','PercentText','Progress','DetailText','PlayButton','VersionLabel','UpdateNotice','UpdateHeading','UpdateCard','ConnectionButton')){$ui[$name]=$window.FindName($name)}
$version=(Get-Content (Join-Path $root 'InstalledVersions.json') -Raw|ConvertFrom-Json).launcher;$ui.VersionLabel.Text='LAUNCHER '+$version
$script:images=@();foreach($name in @('avengers-endgame.jpg','avengers-infinity-war.jpg')){$bitmap=[Windows.Media.Imaging.BitmapImage]::new();$bitmap.BeginInit();$bitmap.CacheOption='OnLoad';$bitmap.UriSource=[Uri]::new((Join-Path $root "Assets/$name"));$bitmap.EndInit();$bitmap.Freeze();$script:images+=,$bitmap}
$ui.HeroImage.Source=$script:images[0];$script:filmIndex=0
$artTimer=[Windows.Threading.DispatcherTimer]::new();$artTimer.Interval=[TimeSpan]::FromSeconds(18);$artTimer.Add_Tick({$script:filmIndex=1-$script:filmIndex;$ui.HeroImage.Source=$script:images[$script:filmIndex]})
$script:verified=$false;$script:busy=$false;$script:recoveryRequired=$false;$script:worker=$null;$script:workerAction='';$script:available=$false;$script:fullAvailable=$false;$script:installed=$false;$script:restart=$false
$workerLog=Join-Path $root '.updates/result.txt';$workerError=Join-Path $root '.updates/error.txt';$progressFile=Join-Path $root '.updates/progress.json'
$connectionState=@{process=$null};$connectionTimer=[Windows.Threading.DispatcherTimer]::new();$connectionTimer.Interval=[TimeSpan]::FromMilliseconds(300)
function Start-ConnectionCheck {
 if($connectionState.process -and -not $connectionState.process.HasExited){return}
 [IO.Directory]::CreateDirectory((Join-Path $root '.updates'))|Out-Null
 $ui.ConnectionButton.Content='Checking server...'
 $args='-NoProfile -ExecutionPolicy Bypass -File "{0}" -CheckConnection' -f (Join-Path $root 'StartGame.ps1')
 $connectionState.process=Start-Process (Get-Process -Id $PID).Path -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput (Join-Path $root '.updates/connection.json') -RedirectStandardError (Join-Path $root '.updates/connection-error.txt') -PassThru
 $connectionTimer.Start()
}
$connectionTimer.Add_Tick({
 if(-not $connectionState.process.HasExited){return};$connectionTimer.Stop()
 try{$report=Read-SharedText (Join-Path $root '.updates/connection.json')|ConvertFrom-Json;$ui.ConnectionButton.Content=if($report.Reachable){'Server reachable  ·  Login help'}else{'Connection problem  ·  Get help'};$ui.ConnectionButton.ToolTip=($report.Checks|ForEach-Object {"$($_.Name): $($_.Message)"}) -join "`n"}catch{$ui.ConnectionButton.Content='Connection check failed  ·  Get help'}
})
function Refresh-Game {
 $script:installed=$false
 if(Test-Path -LiteralPath $saved.ClientPath){$script:installed=$null -ne (Get-ChildItem -LiteralPath $saved.ClientPath -Recurse -Filter MarvelHeroesOmega.exe -File -ErrorAction SilentlyContinue|Where-Object {$_.FullName -match '\\Win64\\' -and $_.FullName -notmatch '\\.mh-updates\\'}|Select-Object -First 1)}
 $ui.GameLocation.Text=$saved.ClientPath
 $ui.PlayButton.Content=if($script:installed){'PLAY'}else{'INSTALL GAME'}
 Sync-UpdateState
}
function Sync-UpdateState {
 $ui.PlayButton.IsEnabled=$script:verified -and -not $script:available -and -not $script:busy -and -not $script:recoveryRequired
 $ui.PlayButton.ToolTip=if($script:available){'Install the required update to unlock Play.'}elseif(-not $script:verified){'Check for updates before playing.'}else{$null}
 $ui.UpdateNotice.Visibility=if($script:available){'Visible'}else{'Collapsed'}
 $ui.UpdateHeading.Text=if($script:available){'UPDATE REQUIRED'}else{'LATEST UPDATES'}
 $ui.UpdateCard.BorderBrush=if($script:available){[Windows.Media.BrushConverter]::new().ConvertFromString('#D4AF62')}else{$window.FindResource('GlassEdge')}
 $ui.UpdateButton.Content=if($script:available){'INSTALL UPDATE'}else{'Check for updates'}
 $ui.UpdateButton.Background=if($script:available){[Windows.Media.BrushConverter]::new().ConvertFromString('#D4AF62')}else{[Windows.Media.BrushConverter]::new().ConvertFromString('#151515')}
 $ui.UpdateButton.Foreground=if($script:available){[Windows.Media.Brushes]::Black}else{[Windows.Media.BrushConverter]::new().ConvertFromString('#E6D29D')}
 if($script:available -and -not $script:busy){$ui.StatusText.Text='Update required before playing.';$ui.DetailText.Text='Select INSTALL UPDATE above. Play unlocks after installation completes.'}
}
function Set-Busy([bool]$Busy){$script:busy=$Busy;foreach($key in @('SettingsButton','AccountButton','FolderButton','LocateButton','UpdateButton')){$ui[$key].IsEnabled=-not $Busy};Sync-UpdateState}
function Select-GameFolder([bool]$Existing){
 $dialog=[System.Windows.Forms.FolderBrowserDialog]::new();$dialog.Description=if($Existing){'Select the folder containing your Marvel Heroes game'}else{'Choose a dedicated game installation folder'};$dialog.UseDescriptionForTitle=$true
 $dialog.SelectedPath=$saved.ClientPath
 if($dialog.ShowDialog() -eq 'OK'){
  $picked=[IO.Path]::GetFullPath($dialog.SelectedPath)
  if($picked.TrimEnd('\') -eq [IO.Path]::GetPathRoot($picked).TrimEnd('\') -or $picked.TrimEnd('\') -eq $root.TrimEnd('\')){[void][System.Windows.MessageBox]::Show('Choose a dedicated game folder, not a drive root or launcher folder.');$dialog.Dispose();return}
  if($Existing -and -not(Get-ChildItem -LiteralPath $picked -Recurse -File -Filter MarvelHeroesOmega.exe -ErrorAction SilentlyContinue|Where-Object {$_.FullName -match '\\Win64\\' -and $_.FullName -notmatch '\\.mh-updates\\'}|Select-Object -First 1)){[void][System.Windows.MessageBox]::Show('No Win64 Marvel Heroes client was found in that folder.');$dialog.Dispose();return}
  $saved.ClientPath=$picked;Save-Settings;Refresh-Game
  $script:verified=$false;Start-Worker 'Check'
 }
 $dialog.Dispose()
}
$ui.FolderButton.Add_Click({Select-GameFolder $false});$ui.LocateButton.Add_Click({Select-GameFolder $true})
function Show-GameSettings {
 $dialog=[System.Windows.Forms.Form]::new();$dialog.Text='Game settings';$dialog.ClientSize=[Drawing.Size]::new(560,510);$dialog.StartPosition='CenterScreen';$dialog.FormBorderStyle='FixedDialog';$dialog.MaximizeBox=$false;$dialog.BackColor=[Drawing.Color]::Black;$dialog.ForeColor=[Drawing.Color]::FromArgb(230,210,157);$dialog.Font=[Drawing.Font]::new('Segoe UI',11)
 $label=[System.Windows.Forms.Label]::new();$label.Text='Resolution';$label.SetBounds(24,24,470,25);$dialog.Controls.Add($label)
 $resolution=[System.Windows.Forms.ComboBox]::new();$resolution.SetBounds(24,55,470,32);$resolution.DropDownStyle='DropDownList';$resolution.Items.AddRange([object[]]$choices);$resolution.SelectedItem=$saved.Resolution;$dialog.Controls.Add($resolution)
 $label2=[System.Windows.Forms.Label]::new();$label2.Text='Display mode';$label2.SetBounds(24,110,470,25);$dialog.Controls.Add($label2)
 $mode=[System.Windows.Forms.ComboBox]::new();$mode.SetBounds(24,141,510,32);$mode.DropDownStyle='DropDownList';$mode.Items.AddRange([object[]]@('Windowed','Fullscreen','Borderless'));$mode.SelectedItem=$saved.Mode;$dialog.Controls.Add($mode)
 Initialize-DisplayApi
 $screens=@([Windows.Forms.Screen]::AllScreens);$monitor=[Windows.Forms.ComboBox]::new();$monitor.SetBounds(24,222,510,32);$monitor.DropDownStyle='DropDownList';$monitor.SelectedIndex=-1
 $screenLabel=[Windows.Forms.Label]::new();$screenLabel.Text='Monitor (detected resolution)';$screenLabel.SetBounds(24,191,510,25);$dialog.Controls.Add($screenLabel)
 for($i=0;$i -lt $screens.Count;$i++){$native=[MHDisplay]::Current($screens[$i].DeviceName);$null=$monitor.Items.Add(('Monitor {0}: {1} x {2}{3}' -f ($i+1),$native.width,$native.height,$(if($screens[$i].Primary){' (primary)'}else{''})));if($screens[$i].DeviceName -eq $saved.Monitor -or (-not $saved.Monitor -and $screens[$i].Primary)){$monitor.SelectedIndex=$i}}
 if($monitor.SelectedIndex -lt 0){$monitor.SelectedIndex=0};$dialog.Controls.Add($monitor)
 $hint=[System.Windows.Forms.Label]::new();$hint.Text='Automatic uses the selected monitor''s resolution. Borderless fills that monitor at its native resolution. Choices are saved for this Windows user.';$hint.SetBounds(24,270,510,64);$hint.ForeColor=[Drawing.Color]::Silver;$dialog.Controls.Add($hint)
 $protect=[Windows.Forms.Button]::new();$protect.Text='Protect additional client fixes...';$protect.SetBounds(24,350,310,34);$dialog.Controls.Add($protect)
 $protect.Add_Click({
  $picker=[Windows.Forms.OpenFileDialog]::new();$picker.InitialDirectory=$saved.ClientPath;$picker.Multiselect=$true;$picker.Title='Choose client fixes to preserve during updates'
  try{if($picker.ShowDialog() -eq 'OK'){
   $list=Join-Path $saved.ClientPath '.mh-protected-files.json';$paths=@();if(Test-Path $list){$paths=@((Read-SharedText $list|ConvertFrom-Json).paths)}
   foreach($file in $picker.FileNames){$relative=[IO.Path]::GetRelativePath($saved.ClientPath,$file).Replace('\','/');$null=Get-SafePath $saved.ClientPath $relative;$paths+=,$relative}
   Write-JsonAtomic @{paths=@($paths|Select-Object -Unique)} $list;$hint.Text='Selected fixes are protected. Existing game executable and display configuration are protected automatically.'
  }}catch{[void][Windows.Forms.MessageBox]::Show('Choose files inside your game folder. '+$_.Exception.Message,'Protect client fixes')}finally{$picker.Dispose()}
 })
 $shortcut=[Windows.Forms.Button]::new();$shortcut.Text='Create desktop shortcut';$shortcut.SetBounds(24,400,310,34);$dialog.Controls.Add($shortcut)
 $shortcut.Add_Click({try{New-LauncherShortcut;$hint.Text='Desktop shortcut created for this Windows user.'}catch{$hint.Text='Could not create the shortcut. '+$_.Exception.Message}})
 $ok=[System.Windows.Forms.Button]::new();$ok.Text='Save';$ok.SetBounds(384,458,150,34);$ok.BackColor=[Drawing.Color]::FromArgb(212,175,98);$ok.ForeColor=[Drawing.Color]::Black;$ok.FlatStyle='Flat';$ok.DialogResult='OK';$dialog.Controls.Add($ok)
 if($ValidateOnly){if($PreviewSettings -and $PreviewPath){Export-FormPreview $dialog $PreviewPath};$dialog.Dispose();return}
 if($dialog.ShowDialog() -eq 'OK'){$saved.Resolution=[string]$resolution.SelectedItem;$saved.Mode=[string]$mode.SelectedItem;$saved.Monitor=$screens[$monitor.SelectedIndex].DeviceName;Save-Settings};$dialog.Dispose()
}
$ui.SettingsButton.Add_Click({Show-GameSettings})
$ui.AccountButton.Add_Click({Open-AccountForm})
$ui.ConnectionButton.Add_Click({Start-Process (Get-Process -Id $PID).Path -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -ConnectionHelp' -f (Join-Path $root 'CreateAccount.ps1')) -WindowStyle Hidden})
$workerTimer=[Windows.Threading.DispatcherTimer]::new();$workerTimer.Interval=[TimeSpan]::FromMilliseconds(200)
function Start-Worker([string]$Action){
 if($Action -eq 'Launch' -and (-not $script:verified -or $script:available -or $script:recoveryRequired)){Sync-UpdateState;return}
 if($Action -eq 'Check'){$script:verified=$false;Sync-UpdateState;Start-ConnectionCheck}
 if($script:worker -and -not $script:worker.HasExited){return}
 if($Action -ne 'Check' -and (Get-Process MarvelHeroesOmega -ErrorAction SilentlyContinue)){$ui.StatusText.Text='The game is already running. Close it before updating.';return}
 Save-Settings;New-Item -ItemType Directory (Join-Path $root '.updates') -Force|Out-Null
 if(Test-Path $progressFile){Remove-Item -LiteralPath $progressFile -Force}
 if($Action -in @('Update','InstallGame')){
  $workerDirectory=Join-Path ([IO.Path]::GetTempPath()) ('MarvelHeroesUpdater-'+[guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($workerDirectory)|Out-Null
  foreach($file in @('Update.ps1','UpdateCore.ps1','Transfer.ps1')){Copy-Item -LiteralPath (Join-Path $root $file) -Destination $workerDirectory}
  $arguments='-NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -HostUI -TargetRoot "{1}" -ParentProcessId {2} -Action {3}' -f (Join-Path $workerDirectory 'Update.ps1'),$root,$PID,$Action
  Start-Process (Get-Process -Id $PID).Path -ArgumentList $arguments -WindowStyle Hidden
  $window.Close();return
 }
 $script:workerAction=$Action
 $scriptFile=if($Action -eq 'Launch'){'StartGame.ps1'}else{'Update.ps1'}
 $arguments='-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root $scriptFile)
 if($Action -ne 'Launch'){$arguments+=' -Action '+$Action}
 $script:worker=Start-Process (Get-Process -Id $PID).Path -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $workerLog -RedirectStandardError $workerError -PassThru
 Set-Busy $true;$ui.Progress.IsIndeterminate=$true;$ui.PercentText.Text=''
 $ui.StatusText.Text=switch($Action){'Check'{'Checking for updates...'}'Launch'{'Opening Marvel Heroes Omega...'}'InstallGame'{'Preparing your game installation...'}default{'Preparing updates...'}}
 $workerTimer.Start()
}
$ui.PlayButton.Add_Click({try{if($script:installed){Start-Worker 'Launch'}elseif($script:fullAvailable){Start-Worker 'InstallGame'}else{$ui.StatusText.Text='Full game download is not published yet. Use Locate existing game.'}}catch{$ui.StatusText.Text=$_.Exception.Message;Set-Busy $false}})
$ui.UpdateButton.Add_Click({try{if($script:available){Start-Worker 'Update'}else{Start-Worker 'Check'}}catch{$ui.StatusText.Text=$_.Exception.Message;Set-Busy $false}})
$workerTimer.Add_Tick({
 if(-not $script:worker.HasExited){
  if(Test-Path $progressFile){try{$progressData=Read-SharedText $progressFile|ConvertFrom-Json;$ui.StatusText.Text=$progressData.message;$ui.Progress.IsIndeterminate=$progressData.percent -lt 0;if($progressData.percent -ge 0){$ui.Progress.Value=$progressData.percent;$ui.PercentText.Text=[string]$progressData.percent+'%'};if($progressData.total -gt 0){$ui.DetailText.Text=('{0:N1} MB / {1:N1} MB' -f ($progressData.done/1MB),($progressData.total/1MB))}}catch{}}
  return
 }
 $workerTimer.Stop();Set-Busy $false;$ui.Progress.IsIndeterminate=$false
 $code=$script:worker.ExitCode
 if($script:workerAction -eq 'Launch' -and $code -eq 0){$window.Close();return}
 if($code -eq 10){$script:restart=$true;$window.Close();return}
 if($code -eq 20){$script:recoveryRequired=$true;Sync-UpdateState;$ui.StatusText.Text='Update recovery is required. Close the game and check for updates again.';return}
 if($code -ne 0){
  if($script:workerAction -eq 'Check'){$ui.StatusText.Text='Cannot verify updates. Retry the update check to unlock Play.';$ui.UpdateSummary.Text='Could not check for updates. Try again later.'}
  else{$message=Get-Content $workerLog -Tail 1;if(-not $message){$message='Operation stopped. See .updates/error.txt for details.'};$ui.StatusText.Text=$message}
 } elseif($script:workerAction -eq 'Check'){
  try{$result=Get-Content $workerLog -Raw|ConvertFrom-Json;$script:verified=$true;$script:recoveryRequired=$false;$script:available=$result.available;$script:fullAvailable=$result.fullAvailable;$ui.UpdateSummary.Text=if($result.available){'Available: '+$result.summary}else{'You have the latest launcher and available patches.'};$ui.UpdateButton.Content=if($result.available){'Install updates'}else{'Check for updates'};$ui.StatusText.Text=if($script:installed){'Ready to assemble.'}elseif($result.fullAvailable){'Choose your installation folder, then select Install Game.'}else{'Use Locate existing game. Full download is coming soon.'}}catch{$ui.StatusText.Text='Unable to read update status. Retry to unlock Play.'}
 } else{Refresh-Game;$ui.UpdateSummary.Text='Installation complete. Checking versions...';Start-Worker 'Check';return}
 $ui.DetailText.Text='Sign in inside the game. Your account progress stays on the server.'
 Sync-UpdateState
})
$window.Add_Closing({param($sender,$eventArgs) if($script:worker -and -not $script:worker.HasExited -and $script:workerAction -in @('Update','InstallGame')){$eventArgs.Cancel=$true;$ui.StatusText.Text='Please wait while the installation finishes.'}})
$window.Add_Closed({$workerTimer.Stop();$artTimer.Stop();$connectionTimer.Stop()})
Refresh-Game
if($ValidateOnly){
 Show-FirstTimeSetup
 Show-GameSettings
 if($ui.Count -ne 18 -or $script:images.Count -ne 2){throw 'Launcher UI is incomplete.'}
 # Exercise the actual button gate, including failed checks and retries.
 foreach($case in @(
  @{verified=$false;available=$false;busy=$false;recovery=$false;enabled=$false},
  @{verified=$true;available=$true;busy=$false;recovery=$false;enabled=$false},
  @{verified=$true;available=$true;busy=$true;recovery=$false;enabled=$false},
  @{verified=$true;available=$false;busy=$true;recovery=$false;enabled=$false},
  @{verified=$true;available=$false;busy=$false;recovery=$true;enabled=$false},
  @{verified=$true;available=$false;busy=$false;recovery=$false;enabled=$true}
 )){
  $script:verified=$case.verified;$script:available=$case.available;$script:busy=$case.busy;$script:recoveryRequired=$case.recovery;Sync-UpdateState
  if($ui.PlayButton.IsEnabled -ne $case.enabled){throw 'Play update gate failed validation.'}
 }
 $script:busy=$false;$script:recoveryRequired=$false;$script:verified=-not $PreviewUpdate;$script:available=[bool]$PreviewUpdate
 if($PreviewUpdate){$ui.UpdateSummary.Text='A new launcher update is ready to install.';$ui.PlayButton.Content='PLAY'}
 Sync-UpdateState
 if($PreviewPath -and -not $PreviewSetup -and -not $PreviewSettings){$window.WindowStartupLocation='Manual';$window.Left=-32000;$window.Top=-32000;$window.ShowInTaskbar=$false;$window.Show();$window.UpdateLayout();$render=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$render.Render($window);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($render));$stream=[IO.File]::Create($PreviewPath);$encoder.Save($stream);$stream.Dispose();$window.Close()}
 Write-Output "Validated launcher, $($choices.Count) display presets, folder selection and two artwork slides.";exit 0
}
Save-Settings
$window.Add_ContentRendered({$artTimer.Start();if(-not $saved.SetupComplete){Show-FirstTimeSetup};try{Start-ConnectionCheck;Start-Worker 'Check'}catch{$ui.StatusText.Text='Unable to check updates. Retry to unlock Play.';Set-Busy $false}})
try{[void]$window.ShowDialog()}finally{if($launcherLock){$launcherLock.Dispose()}}
if($script:restart){Start-Process (Get-Process -Id $PID).Path -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'Play.ps1')) -WindowStyle Hidden}
