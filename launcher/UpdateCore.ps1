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
function Get-PlayerSettingsPath([string]$LauncherRoot){
 $bytes=[Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($LauncherRoot).TrimEnd('\').ToLowerInvariant())
 $key=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).Substring(0,16)
 return Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) "MarvelHeroesLauncher/$key/settings.json"
}
function Get-PlayerSettings([string]$LauncherRoot){
 $settings=@{Resolution='Automatic (monitor resolution)';Mode='Windowed';Monitor='';ClientPath=(Join-Path $LauncherRoot 'Client');SetupComplete=$false}
 $path=Get-PlayerSettingsPath $LauncherRoot
 $existingInstall=(Test-Path -LiteralPath $path) -or (Test-Path -LiteralPath (Join-Path $LauncherRoot 'LauncherSettings.json')) -or (Test-Path -LiteralPath (Join-Path $LauncherRoot '.updates')) -or (Test-Path -LiteralPath (Join-Path $LauncherRoot '.launcher.lock'))
 if(-not(Test-Path -LiteralPath $path)){$path=Join-Path $LauncherRoot 'LauncherSettings.json'}
 if(Test-Path -LiteralPath $path){
  try{$old=Read-SharedText $path|ConvertFrom-Json -AsHashtable;foreach($key in @('Resolution','Monitor','ClientPath','SetupComplete')){if($old.ContainsKey($key)){$settings[$key]=$old[$key]}};if($old.Mode -in @('Windowed','Fullscreen','Borderless')){$settings.Mode=$old.Mode}}catch{throw 'Your saved settings could not be read. Keep a copy of settings.json before repairing it.'}
 }
 $settings.SetupComplete=[bool]$settings.SetupComplete -or $existingInstall
 return $settings
}
function Enter-LauncherInstance([string]$LauncherRoot){
 $key=[IO.Path]::GetFileName([IO.Path]::GetDirectoryName((Get-PlayerSettingsPath $LauncherRoot)))
 $mutex=[Threading.Mutex]::new($false,('Local\MarvelHeroesLauncher-'+$key+'-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
 $acquired=$false
 try{$acquired=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$acquired=$true}
 return [pscustomobject]@{Mutex=$mutex;Acquired=$acquired}
}
function Save-PlayerSettings([string]$LauncherRoot,$Settings){
 $path=Get-PlayerSettingsPath $LauncherRoot
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))|Out-Null
 Write-JsonAtomic $Settings $path
}
function Initialize-DisplayApi {
 if('MHDisplay' -as [type]){return}
 Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MHDisplay {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] public struct Mode {
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string device;
  public short spec,driver,size,extra; public int fields,x,y,orientation,fixedOutput;
  public short color,duplex,yResolution,tt,collate;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string form;
  public short logPixels; public int bits,width,height,flags,frequency,icmMethod,icmIntent,media,dither,reserved1,reserved2,panningWidth,panningHeight;
 }
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern bool EnumDisplaySettings(string device,int index,ref Mode mode);
 [DllImport("user32.dll",SetLastError=true)] static extern int GetWindowLong(IntPtr h,int index);
 [DllImport("user32.dll",SetLastError=true)] static extern int SetWindowLong(IntPtr h,int index,int value);
 [DllImport("user32.dll",SetLastError=true)] static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
 [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h,int command);
 [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
 public static void Activate(IntPtr h){ShowWindow(h,9);SetForegroundWindow(h);}
 [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 public static Mode Current(string device){var m=new Mode();m.size=(short)Marshal.SizeOf<Mode>();if(!EnumDisplaySettings(device,-1,ref m))throw new InvalidOperationException("Cannot detect this monitor's resolution.");return m;}
 public static void Borderless(IntPtr h,int x,int y,int w,int height){
  var previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
  try {ShowWindow(h,9);SetWindowLong(h,-16,GetWindowLong(h,-16)&~0x00C40000);SetWindowLong(h,-20,GetWindowLong(h,-20)&~0x301);
   if(!SetWindowPos(h,IntPtr.Zero,x,y,w,height,0x34))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  } finally {if(previous!=IntPtr.Zero)SetThreadDpiAwarenessContext(previous);}
 }
}
'@
}
function Export-FormPreview($Form,[string]$Path){
 $Form.ShowInTaskbar=$false;$Form.StartPosition='Manual';$Form.Location=[Drawing.Point]::new(-32000,-32000);$Form.Show();[Windows.Forms.Application]::DoEvents()
 $bitmap=[Drawing.Bitmap]::new($Form.Width,$Form.Height)
 try{$Form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$Form.Width,$Form.Height));$bitmap.Save($Path)}finally{$bitmap.Dispose();$Form.Hide()}
}
function Get-GameDisplay($Settings){
 Add-Type -AssemblyName System.Windows.Forms
 Initialize-DisplayApi
 $screen=@([Windows.Forms.Screen]::AllScreens|Where-Object DeviceName -eq $Settings.Monitor)
 $device=if($screen.Count){$screen[0].DeviceName}else{[Windows.Forms.Screen]::PrimaryScreen.DeviceName}
 $native=[MHDisplay]::Current($device)
 $width=$native.width;$height=$native.height
 if($Settings.Mode -ne 'Borderless' -and $Settings.Resolution -ne 'Automatic (monitor resolution)'){
  if($Settings.Resolution -notmatch '^\s*(\d+)\s*x\s*(\d+)') {throw 'Choose a valid resolution in Game settings.'}
  $width=[int]$Matches[1];$height=[int]$Matches[2]
 }
 if($width -lt 640 -or $width -gt 16384 -or $height -lt 480 -or $height -gt 8640){throw 'The selected display resolution is unsupported.'}
 return [pscustomobject]@{Width=$width;Height=$height;X=$native.x;Y=$native.y;Device=$device;NativeWidth=$native.width;NativeHeight=$native.height}
}
function Get-LoginFailureMessage([int]$Code){
 switch($Code){
  200 {'Login accepted. If the game cannot continue, check the game connection and installed client fixes.'}
  {$_ -in @(401,403)} {'Email or password was not accepted. Use your account email, check Caps Lock, and enter the password again.'}
  402 {'This account is banned. Contact the server owner.'}
  404 {'The game could not reach the login service. Run the connection check.'}
  405 {'The account requires email verification. Contact the server owner.'}
  407 {'Accept the terms shown inside the game to continue.'}
  409 {'The server requires a different client version. Check for updates; contact the server owner if none are offered.'}
  411 {'This account is archived. Contact the server owner.'}
  412 {'This password has expired. Contact the server owner to reset it.'}
  417 {'The account has an age restriction. Contact the server owner.'}
  500 {'The login service encountered an error. Wait a moment and retry; contact the server owner if it continues.'}
  503 {'The login service is temporarily unavailable. Wait a moment, then run the connection check again.'}
  default {'The game could not complete login. Run the connection check. If all connections pass, give the server owner the error shown in the game.'}
 }
}
function Test-MarvelConnection([string]$Server='myfamilyflix.duckdns.org',[int]$GamePort=4306){
 $checks=@()
 $handler=[Net.Http.HttpClientHandler]::new();$handler.AllowAutoRedirect=$false
 $http=[Net.Http.HttpClient]::new($handler);$http.Timeout=[TimeSpan]::FromSeconds(6)
 try{
  foreach($route in @(@{name='Configuration';url="http://$Server/SiteConfig.xml"},@{name='Login service';url="https://$Server/AuthServer/Login/IndexPB"})){
   $response=$null
   try{
    $response=$http.GetAsync($route.url).GetAwaiter().GetResult();$code=[int]$response.StatusCode
    if($route.name -eq 'Configuration'){
     $valid=$false
     if($code -eq 200){try{$xml=[xml]$response.Content.ReadAsStringAsync().GetAwaiter().GetResult();$valid=$null -ne $xml.SelectSingleNode('/config/str[@name="AuthServerAddress"]') -and $xml.SelectSingleNode('/config/str[@name="AuthServerPort"]').value -eq '443'}catch{$valid=$false}}
    }else{$valid=$code -eq 405} # GET is intentionally rejected; this is not a player's login result.
    $message=if($valid){'Reachable'}elseif($code -ge 500){'Server unavailable. Try again later.'}else{"Unexpected response ($code). Ask the server owner to check this route."}
    $checks+=,[pscustomobject]@{Name=$route.name;Ok=$valid;Message=$message}
   }catch{$checks+=,[pscustomobject]@{Name=$route.name;Ok=$false;Message='Cannot connect. Check your internet connection, VPN/firewall, and Windows date/time; then retry.'}}finally{if($response){$response.Dispose()}}
  }
 }finally{$http.Dispose();$handler.Dispose()}
 $tcp=[Net.Sockets.TcpClient]::new()
 try{$task=$tcp.ConnectAsync($Server,$GamePort);if(-not $task.Wait(6000) -or -not $tcp.Connected){throw 'Timeout'};$checks+=,[pscustomobject]@{Name='Game connection';Ok=$true;Message='Reachable'}}catch{$checks+=,[pscustomobject]@{Name='Game connection';Ok=$false;Message='Game port is unreachable. Check firewall access or ask the server owner to check the game service and port forwarding.'}}finally{$tcp.Dispose()}
 return [pscustomobject]@{Reachable=(@($checks|Where-Object {-not $_.Ok}).Count -eq 0);CheckedAt=[DateTime]::Now.ToString('HH:mm:ss');Checks=$checks}
}
function Test-ProtectedClientFile([string]$Root,[string]$Relative){
 $path=Get-SafePath $Root $Relative
 if(-not(Test-Path -LiteralPath $path)){return $false}
 if($Relative -match '(?i)(^|/)(Config|Saved|SaveGames|Screenshots)(/|$)|\.ini$|(^|/)MarvelHeroesOmega\.exe$'){return $true}
 $list=Join-Path $Root '.mh-protected-files.json'
 if(Test-Path -LiteralPath $list){
  $data=Read-SharedText $list|ConvertFrom-Json
  foreach($entry in @($data.paths)){$null=Get-SafePath $Root $entry;if($Relative -ieq $entry){return $true}}
 }
 return $false
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
  if(($file.path -like 'Client/*' -or ($file.PSObject.Properties['protectLocal'] -and $file.protectLocal)) -and $exists -and (-not $file.PSObject.Properties['baseSha256'] -or -not $file.baseSha256) -and $oldHash -ne $file.sha256){throw "Your local file '$($file.path)' differs from this update. It was preserved. Protect this fix in Game settings, or ask the server owner for a compatible patch."}
  if($exists -and $file.PSObject.Properties['baseSha256'] -and $file.baseSha256 -and $oldHash -ne $file.baseSha256 -and $oldHash -ne $file.sha256){throw "Local changes detected in '$($file.path)'. Update cancelled without replacing them. Protect this fix in Game settings, or ask the server owner for a compatible patch."}
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




