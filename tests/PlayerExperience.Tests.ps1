$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../launcher/UpdateCore.ps1')
function Check($Condition,[string]$Message){if(-not $Condition){throw $Message};Write-Output "PASS: $Message"}
$testRoot=Join-Path $PSScriptRoot ('sandbox-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($testRoot)|Out-Null
Check (-not (Get-PlayerSettings $testRoot).SetupComplete) 'A genuinely fresh installation gets the welcome guide'
$updatedRoot=Join-Path $testRoot 'updated';[IO.Directory]::CreateDirectory((Join-Path $updatedRoot '.updates'))|Out-Null
Check ((Get-PlayerSettings $updatedRoot).SetupComplete) 'An updated installation skips the welcome guide even before profile migration'
$stale=Join-Path $testRoot '.launcher.lock';$staleHandle=[IO.File]::Open($stale,'OpenOrCreate','ReadWrite','None')
$instance=$null
try{
 $instance=Enter-LauncherInstance $testRoot
 Check $instance.Acquired 'An old or inaccessible lock file cannot falsely report the launcher as open'
 $second=[powershell]::Create();$null=$second.AddScript('param($core,$root) . $core; $instance=Enter-LauncherInstance $root; try { $instance.Acquired } finally { if($instance.Acquired){$instance.Mutex.ReleaseMutex()};$instance.Mutex.Dispose() }').AddArgument((Join-Path $PSScriptRoot '../launcher/UpdateCore.ps1')).AddArgument($testRoot)
 try{$result=$second.Invoke();Check (-not [bool]$result[0]) 'An active launcher still excludes a second instance'}finally{$second.Dispose()}
}finally{if($instance -and $instance.Acquired){$instance.Mutex.ReleaseMutex();$instance.Mutex.Dispose()};$staleHandle.Dispose()}
$legacy=Join-Path $testRoot 'LauncherSettings.json'
Write-JsonAtomic @{Resolution='3440 x 1440  |  Ultrawide 21:9';Mode='Fullscreen';ClientPath=(Join-Path $testRoot 'Game')} $legacy
$settings=Get-PlayerSettings $testRoot
Check ($settings.Mode -eq 'Fullscreen' -and $settings.Resolution -like '3440*') 'Existing display choices migrate without changing them'
Check ($settings.Server -eq 'Live') 'Existing players default to Live Server'
Check $settings.SetupComplete 'Existing player settings suppress first-run pages'
$settings.Mode='Borderless';$settings.SetupComplete=$true;$settings.Server='Test';Save-PlayerSettings $testRoot $settings
$settings.Server='Test';Write-JsonAtomic $settings (Get-PlayerSettingsPath $testRoot)
try {
 Write-JsonAtomic @{Resolution='1280 x 720';Mode='Windowed'} $legacy
 $loaded=Get-PlayerSettings $testRoot
 Check ($loaded.Mode -eq 'Borderless' -and $loaded.SetupComplete -and $loaded.Resolution -like '3440*') 'Per-user choices survive replacement of legacy launcher settings'
 Check ($loaded.Server -eq 'Live') 'Retired server selections migrate to Live without losing settings'
 $live=Get-ServerProfile Live;$legacy=Get-ServerProfile 'Test'
 Check ($legacy.SiteConfig -eq $live.SiteConfig -and $legacy.GamePort -eq 4306 -and $legacy.Registration -eq $live.Registration) 'Legacy profile requests resolve only to Live'
 $displayStub=[pscustomobject]@{Width=1920;Height=1080}
 $loaded.Server='Test';$liveArgs=Get-GameLaunchArguments $loaded $displayStub
 Check ($liveArgs.Contains('-siteconfigurl='+$live.SiteConfig) -and -not $liveArgs.Contains('SiteConfigTest')) 'Legacy settings cannot launch a retired server'
 Check ((Get-PlayerSettingsPath $testRoot).StartsWith([Environment]::GetFolderPath('LocalApplicationData'))) 'Player settings live outside the launcher update folder'
 $display=Get-GameDisplay $loaded
 Check ($display.Width -eq $display.NativeWidth -and $display.Height -eq $display.NativeHeight) 'Borderless uses detected native resolution'
 $loaded.Mode='Windowed';$loaded.Resolution='Automatic (monitor resolution)';$loaded.Monitor='disconnected-monitor'
 $automatic=Get-GameDisplay $loaded
 Check ($automatic.Width -eq $automatic.NativeWidth -and $automatic.Height -eq $automatic.NativeHeight) 'Automatic resolution falls back to an attached monitor'
 $loaded.Resolution='1280 x 720';$manual=Get-GameDisplay $loaded
 Check ($manual.Width -eq 1280 -and $manual.Height -eq 720) 'Manual resolution remains available'
 Add-Type -AssemblyName System.Windows.Forms
 Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MHWindowTest {
 [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h,int index);
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int left,top,right,bottom; }
 [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out Rect rect);
 [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 public static bool Verify(IntPtr h){var old=SetThreadDpiAwarenessContext(new IntPtr(-4));try{Rect r;GetWindowRect(h,out r);return (GetWindowLong(h,-16)&0x00C40000)==0 && r.right-r.left==800 && r.bottom-r.top==600;}finally{if(old!=IntPtr.Zero)SetThreadDpiAwarenessContext(old);}}
}
'@
 $form=[Windows.Forms.Form]::new();$form.Opacity=0;$form.ShowInTaskbar=$false
 try{[MHDisplay]::Borderless($form.Handle,-32000,-32000,800,600);Check ([MHWindowTest]::Verify($form.Handle)) 'Borderless removes the real Windows frame and applies exact pixel bounds'}finally{$form.Dispose()}
}finally{$path=Get-PlayerSettingsPath $testRoot;if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path};$directory=[IO.Path]::GetDirectoryName($path);if(Test-Path -LiteralPath $directory){Remove-Item -LiteralPath $directory}}
$client=Join-Path $testRoot 'client';$stage=Join-Path $testRoot 'stage'
foreach($root in @($client,$stage)){[IO.Directory]::CreateDirectory((Join-Path $root 'Win64'))|Out-Null;[IO.Directory]::CreateDirectory((Join-Path $root 'Config'))|Out-Null}
foreach($relative in @('Win64/MarvelHeroesOmega.exe','Config/Display.ini','Win64/custom-fix.dll','content.bin')){[IO.File]::WriteAllText((Join-Path $client $relative),'player-customization');[IO.File]::WriteAllText((Join-Path $stage $relative),'updated-content')}
Write-JsonAtomic @{paths=@('Win64/custom-fix.dll')} (Join-Path $client '.mh-protected-files.json')
$files=@();foreach($relative in @('Win64/MarvelHeroesOmega.exe','Config/Display.ini','Win64/custom-fix.dll','content.bin')){if(Test-ProtectedClientFile $client $relative){continue};$file=Join-Path $stage $relative;$files+=,[pscustomobject]@{path=$relative;sha256=(Get-FileHash $file).Hash;size=(Get-Item $file).Length}}
$transaction=Join-Path $testRoot 'transaction';[IO.Directory]::CreateDirectory($transaction)|Out-Null
Install-Transaction $client $stage $transaction $files
foreach($relative in @('Win64/MarvelHeroesOmega.exe','Config/Display.ini','Win64/custom-fix.dll')){Check ((Read-SharedText (Join-Path $client $relative)) -eq 'player-customization') "Update preserves $relative"}
Check ((Read-SharedText (Join-Path $client 'content.bin')) -eq 'updated-content') 'Unprotected game content still updates'
Check (-not (Test-ProtectedClientFile $client 'Config/New.ini')) 'A first installation can create missing configuration files'
Check ((Get-LoginFailureMessage 401) -match 'Email or password') 'Wrong-password errors have clear recovery instructions'
Check ((Get-LoginFailureMessage 409) -match 'client version') 'Client-version mismatch has a separate explanation'
Check ((Get-LoginFailureMessage 503) -match 'temporarily unavailable') 'Service failures are distinct from credential failures'
$failed=Test-MarvelConnection -Server '127.0.0.1' -GamePort 1
Check (-not $failed.Reachable -and @($failed.Checks).Count -eq 3 -and -not $failed.Checks[2].Ok) 'Connection diagnostics report an unreachable game port separately'
Write-Output 'All player experience tests passed.'
