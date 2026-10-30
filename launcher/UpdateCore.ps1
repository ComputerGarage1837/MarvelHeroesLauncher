Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Get-UpdateChangelogText($Packages){
 $sections=@()
 foreach($package in @($Packages)){
  if($null -eq $package -or -not $package.PSObject.Properties['component']){continue}
  $label=switch([string]$package.component){'launcher'{'Launcher'}'client'{'Game'}'client-full'{'Game installation'}default{'Update'}}
  $changes=if($package.PSObject.Properties['changes']){@($package.changes|Where-Object {$_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_)}|ForEach-Object {$_.Trim()})}else{@()}
  $body=if(@($changes).Count){(($changes|ForEach-Object {'• '+$_}) -join "`n")}else{'No changelog is available for this update.'}
  $sections+=($label+' '+[string]$package.version+"`n"+$body)
 }
 if(-not $sections.Count){return 'No changelog is available for this update.'}
 return ($sections -join "`n`n")
}
function Select-UpdateChangelogPackages($Pending,$All){
 if(@($Pending|Where-Object {$null -ne $_}).Count){return @($Pending)}
 return @($All|Where-Object {$_.PSObject.Properties['changes'] -and $_.component -in @('client','launcher')}|Select-Object -Last 2)
}
function Ensure-NativeLauncher([string]$Root){
 $source=@'
using System;
using System.IO;
using System.Linq;
using System.Diagnostics;
using System.Windows.Forms;
class Bootstrap {
 static string Quote(string s) {
  var b=new System.Text.StringBuilder("\"");int slashes=0;
  foreach(char c in s){if(c=='\\'){slashes++;continue;}if(c=='"'){b.Append('\\',slashes*2+1);b.Append(c);}else{b.Append('\\',slashes);b.Append(c);}slashes=0;}
  b.Append('\\',slashes*2);b.Append('"');return b.ToString();
 }
 [STAThread] static int Main(string[] args) {
  try {
   string root=AppDomain.CurrentDomain.BaseDirectory;
   string[] candidates={Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),@"PowerShell\7\pwsh.exe"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),@".cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe")};
   string exe=candidates.FirstOrDefault(File.Exists);
   if(exe==null) foreach(string p in (Environment.GetEnvironmentVariable("PATH")??"").Split(';')) {string f=Path.Combine(p.Trim('"'),"pwsh.exe");if(File.Exists(f)){exe=f;break;}}
   if(exe==null) throw new Exception("Install PowerShell 7 for Windows, then open the launcher again.");
   var info=new ProcessStartInfo(exe,"-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "+Quote(Path.Combine(root,"Play.ps1"))+" "+string.Join(" ",args.Select(Quote).ToArray()));
   info.UseShellExecute=false;info.CreateNoWindow=true;info.WindowStyle=ProcessWindowStyle.Hidden;info.WorkingDirectory=root;
   using(var child=Process.Start(info)){if(args.Contains("-ValidateOnly")){child.WaitForExit();return child.ExitCode;}}
   return 0;
  }catch(Exception e){MessageBox.Show(e.Message,"Marvel Heroes Launcher",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}
 }
}
'@
 # Hash both the source and executable so upgrades rebuild once without replacing a running entry point.
 $sha=[Security.Cryptography.SHA256]::Create();try{$sourceHash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($source))).Replace('-','')}finally{$sha.Dispose()}
 $destination=Join-Path $Root 'MarvelHeroesLauncher.exe';$marker=Join-Path $Root 'LauncherBootstrap.json'
 if((Test-Path -LiteralPath $destination) -and (Test-Path -LiteralPath $marker)){
  try{$saved=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json;if($saved.sourceHash -eq $sourceHash -and $saved.exeHash -eq (Get-FileHash -LiteralPath $destination).Hash){return $destination}}catch{}
 }
 $temp=Join-Path ([IO.Path]::GetTempPath()) ('MarvelLauncher-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $temp|Out-Null
 try{
  $cs=Join-Path $temp 'Bootstrap.cs';$exe=Join-Path $temp 'MarvelHeroesLauncher.exe';[IO.File]::WriteAllText($cs,$source)
  $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
  $result=& $compiler /nologo /target:winexe /platform:anycpu /reference:System.Windows.Forms.dll /reference:System.Core.dll "/out:$exe" $cs 2>&1
  if($LASTEXITCODE -ne 0){throw ('Could not create the Windows launcher: '+($result -join ' '))}
  Copy-Item -LiteralPath $exe -Destination $destination -Force
  @{sourceHash=$sourceHash;exeHash=(Get-FileHash -LiteralPath $destination).Hash}|ConvertTo-Json|Set-Content -LiteralPath $marker
 }finally{if([IO.Path]::GetFullPath($temp).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $temp -Recurse -Force}}
 return $destination
}
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
function Find-ClientRoot([string]$Selected,[switch]$SearchDescendants){
 if(-not $Selected -or -not (Test-Path -LiteralPath $Selected -PathType Container)){return $null}
 $selectedPath=[IO.Path]::GetFullPath($Selected)
 $suffix='UnrealEngine3\Binaries\Win64\MarvelHeroesOmega.exe'
 foreach($candidate in @($selectedPath,(Join-Path $selectedPath 'Client'))){
  if(Test-Path -LiteralPath (Join-Path $candidate $suffix) -PathType Leaf){return $candidate}
 }
 if(-not $SearchDescendants){return $null}
 $matches=@(Get-ChildItem -LiteralPath $selectedPath -Recurse -Filter 'MarvelHeroesOmega.exe' -File -ErrorAction SilentlyContinue | Where-Object {$_.FullName.EndsWith('\'+$suffix,[StringComparison]::OrdinalIgnoreCase) -and $_.FullName -notmatch '\\.mh-updates\\'})
 if($matches.Count -ne 1){return $null}
 return $matches[0].FullName.Substring(0,$matches[0].FullName.Length-$suffix.Length-1)
}
function Get-PlayerSettingsPath([string]$LauncherRoot){
 $bytes=[Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($LauncherRoot).TrimEnd('\').ToLowerInvariant())
 $key=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).Substring(0,16)
 return Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) "MarvelHeroesLauncher/$key/settings.json"
}
function Get-PlayerSettings([string]$LauncherRoot){
 $settings=@{Resolution='Automatic (monitor resolution)';Mode='Windowed';Monitor='';ClientPath=(Join-Path $LauncherRoot 'Client');SetupComplete=$false;Server='Live'}
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
 $Settings.Server='Live'
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
function Get-ServerProfile([string]$Name='Live'){
 # Accept a legacy profile argument while always resolving the remaining Live service.
 return [pscustomobject]@{Key='Live';Name='Live Server';SiteConfig='http://myfamilyflix.duckdns.org/SiteConfig.xml';Auth='https://myfamilyflix.duckdns.org/AuthServer/Login/IndexPB';Registration='https://myfamilyflix.duckdns.org/marvel/accounts/create';GameHost='myfamilyflix.duckdns.org';GamePort=4306;Notice=''}
}
function Get-GameLaunchArguments($Settings,$Display){
 $profile=Get-ServerProfile $Settings.Server
 $mode=if($Settings.Mode -eq 'Borderless'){'Windowed'}else{[string]$Settings.Mode}
 if($mode -notin @('Windowed','Fullscreen')){throw 'Invalid display mode.'}
 return "-robocopy -nosteam -siteconfigurl=$($profile.SiteConfig) -ResX=$($Display.Width) -ResY=$($Display.Height) -$mode"
}
function Test-MarvelConnection([string]$Server='',[int]$GamePort=0,[string]$Profile='Live'){
 $selected=Get-ServerProfile $Profile
 $hostName=if($Server){$Server}else{$selected.GameHost};if(-not $GamePort){$GamePort=$selected.GamePort}
 $configUrl=if($Server){"http://$Server/SiteConfig.xml"}else{$selected.SiteConfig}
 $authUrl=if($Server){"https://$Server/AuthServer/Login/IndexPB"}else{$selected.Auth}
 $checks=@()
 $handler=[Net.Http.HttpClientHandler]::new();$handler.AllowAutoRedirect=$false
 $http=[Net.Http.HttpClient]::new($handler);$http.Timeout=[TimeSpan]::FromSeconds(6)
 try{
  foreach($route in @(@{name='Configuration';url=$configUrl},@{name='Login service';url=$authUrl})){
   $response=$null
   try{
    $response=$http.GetAsync($route.url).GetAwaiter().GetResult();$code=[int]$response.StatusCode
    if($route.name -eq 'Configuration'){
     $valid=$false
     if($code -eq 200){try{$xml=[xml]$response.Content.ReadAsStringAsync().GetAwaiter().GetResult();$expectedAuth=[Uri]$authUrl;$valid=$xml.SelectSingleNode('/config/str[@name="AuthServerAddress"]').value -eq $expectedAuth.Host -and $xml.SelectSingleNode('/config/str[@name="AuthServerPort"]').value -eq '443' -and $xml.SelectSingleNode('/config/str[@name="AuthServerUrl"]').value -eq $expectedAuth.AbsolutePath}catch{$valid=$false}}
    }else{$valid=$code -eq 405} # GET is intentionally rejected; this is not a player's login result.
    $message=if($valid){'Reachable'}elseif($code -ge 500){'Server unavailable. Try again later.'}else{"Unexpected response ($code). Ask the server owner to check this route."}
    $checks+=,[pscustomobject]@{Name=$route.name;Ok=$valid;Message=$message}
   }catch{$checks+=,[pscustomobject]@{Name=$route.name;Ok=$false;Message='Cannot connect. Check your internet connection, VPN/firewall, and Windows date/time; then retry.'}}finally{if($response){$response.Dispose()}}
  }
 }finally{$http.Dispose();$handler.Dispose()}
 $tcp=[Net.Sockets.TcpClient]::new()
 try{$task=$tcp.ConnectAsync($hostName,$GamePort);if(-not $task.Wait(6000) -or -not $tcp.Connected){throw 'Timeout'};$checks+=,[pscustomobject]@{Name='Game connection';Ok=$true;Message='Reachable'}}catch{$checks+=,[pscustomobject]@{Name='Game connection';Ok=$false;Message='Game port is unreachable. Check firewall access or ask the server owner to check the game service and port forwarding.'}}finally{$tcp.Dispose()}
 return [pscustomobject]@{Server=$Profile;ServerName=$selected.Name;Reachable=(@($checks|Where-Object {-not $_.Ok}).Count -eq 0);CheckedAt=[DateTime]::Now.ToString('HH:mm:ss');Checks=$checks}
}
function Get-CameraInputEntries([string]$Text){
 $section='';$index=0
 foreach($line in [regex]::Split($Text,'(?<=\n)')){
  if($line -match '^\s*\[([^]]+)\]'){$section=$Matches[1]}
  elseif($line -match '^\s*([.!+\-]?)(Bindings|ControllerBindings)\s*=\s*\(([^\r\n]*)\)\s*$'){
   $prefix=$Matches[1];$kind=$Matches[2];$body=$Matches[3]
   $name=[regex]::Match($body,'(?i)(?:^|,)\s*Name\s*=\s*"([^"]+)"')
   $command=[regex]::Match($body,'(?i)(?:^|,)\s*Command\s*=\s*(?:"([^"]*)"|([^,)]*))')
   if($name.Success -and $command.Success){
    [pscustomobject]@{Section=$section;Prefix=$prefix;Kind=$kind;Name=$name.Groups[1].Value;Command=$(if($command.Groups[1].Success){$command.Groups[1].Value}else{$command.Groups[2].Value.Trim()});Plain=($body -notmatch '(?i)(?:^|,)\s*(?:Control|Shift|Alt)\s*=\s*True');Index=$index;Raw=$line}
   }
  }
  $index++
 }
}
function Get-CameraControlConflict($Entries){
 foreach($entry in $Entries){
  if($entry.Section -ine 'MarvelGame.MarvelInput' -or $entry.Kind -ine 'Bindings' -or -not $entry.Plain){continue}
  if($entry.Name -ieq 'MiddleMouseButton' -and $entry.Command -notmatch '^KBM_MMB[AB]?$'){return 'Middle mouse already has a custom command. Camera controls were left unchanged.'}
  if($entry.Name -match '^Mouse[XY]$' -and $entry.Command -notmatch '^KBM_(?:Cam[XY][ABC]?|None)$' -and $entry.Command){return 'Custom mouse-axis controls were found. Camera controls were left unchanged to preserve them.'}
 }
 return ''
}
function Update-CameraInputText([string]$Text){
 $entries=@(Get-CameraInputEntries $Text);$conflict=Get-CameraControlConflict $entries
 if($conflict){return [pscustomobject]@{Text=$Text;Conflict=$conflict}}
 $lines=[regex]::Split($Text,'(?<=\n)');$newline=if($Text.Contains("`r`n")){"`r`n"}else{"`n"}
 $commands=[ordered]@{
  KBM_CamX='Axis GamepadRawJoyLookRight Speed=0.1667'
  KBM_CamY='Axis GamepadRawJoyLookUp Speed=-0.1667'
  KBM_None=''
  KBM_MMB='SetBind MouseX KBM_CamX | SetBind MouseY KBM_CamY | OnRelease SetBind MouseX KBM_None | OnRelease SetBind MouseY KBM_None'
  MiddleMouseButton='KBM_MMB'
 }
 $last=@{};$drop=[Collections.Generic.HashSet[int]]::new();$replacements=@{}
 foreach($entry in $entries){
  if($entry.Section -ieq 'MarvelGame.MarvelInput' -and $entry.Kind -ieq 'Bindings'){
   # Each existing array representation needs its own aliases, including both sides of the saved user-settings diff.
   # A single prefix selected for the whole section leaves generated Bindings and +Bindings without the camera commands.
   if($entry.Prefix -in @('','.','+','!')){$last[$entry.Prefix]=$entry.Index}
   if($entry.Plain){
    $managed=$commands.Contains($entry.Name)
    $oldToggle=($entry.Name -in @('KBM_ToggleOn','KBM_ToggleOff')) -or ($entry.Name -ieq 'F7' -and $entry.Command -match '^KBM_Toggle(?:On|Off)$')
    $savedAxis=$entry.Name -match '^Mouse[XY]$' -and $entry.Command -match '^KBM_(?:Cam[XY][ABC]?|None)$'
    if($managed -or $oldToggle -or $savedAxis){[void]$drop.Add($entry.Index)}
   }
  }
  if($entry.Section -in @('MarvelGame.MarvelInput','KeyBindings_Classic','KeyBindings_Concar') -and $entry.Name -ieq 'XboxTypeS_RightShoulder' -and $entry.Plain -and $entry.Command -ceq 'TargetLockOnToggle'){
   $replacements[$entry.Index]=[regex]::Replace($entry.Raw,'(?i)(Command\s*=\s*")TargetLockOnToggle(")','$1TargetLockOnToggle | VFXToggleOtherPlayerPowerEffects | OnRelease VFXTogglePowerDecals$2')
  }
 }
 $output=[Text.StringBuilder]::new()
 for($i=0;$i -lt $lines.Length;$i++){
  if($replacements.ContainsKey($i)){[void]$output.Append($replacements[$i])}
  elseif(-not $drop.Contains($i)){[void]$output.Append($lines[$i])}
  foreach($prefix in @('','.','!','+')){
   if(-not $last.ContainsKey($prefix) -or $last[$prefix] -ne $i){continue}
   if($output.Length -and $output[$output.Length-1] -ne "`n"){[void]$output.Append($newline)}
   foreach($name in $commands.Keys){
    $flags=if($prefix -eq '.') {''} else {',Control=False,Shift=False,Alt=False,bIgnoreCtrl=False,bIgnoreShift=False,bIgnoreAlt=False'}
    [void]$output.Append($prefix+'Bindings=(Name="'+$name+'",Command="'+$commands[$name]+'"'+$flags+')'+$newline)
   }
  }
 }
 return [pscustomobject]@{Text=$output.ToString();Conflict=''}
}
function Set-CameraInputFiles([string]$GameRoot,[string[]]$Files){
 $plans=@();$all=@()
 foreach($path in $Files){
  if(-not (Test-Path -LiteralPath $path)){continue}
  $reader=[IO.StreamReader]::new($path,$true);try{$text=$reader.ReadToEnd();$encoding=$reader.CurrentEncoding}finally{$reader.Dispose()}
  if($encoding.CodePage -eq 65001){$bytes=[IO.File]::ReadAllBytes($path);$bom=$bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191;$encoding=[Text.UTF8Encoding]::new($bom)}
  $all+=@(Get-CameraInputEntries $text)
  $updated=Update-CameraInputText $text
  if($updated.Text -cne $text){$plans+=,[pscustomobject]@{Path=$path;Original=$text;Updated=$updated.Text;Encoding=$encoding;Backup='';Temp=''}}
 }
 $conflict=Get-CameraControlConflict $all
 if($conflict){return [pscustomobject]@{Status='CustomControls';Message=$conflict;ChangedFiles=0}}
 $backupDirectory=Join-Path $GameRoot '.mh-camera-control-backups';$committed=@()
 try{
  foreach($plan in $plans){
   if((Get-Item -LiteralPath $plan.Path).IsReadOnly){throw 'An input file is read-only. No controls were changed.'}
   [IO.Directory]::CreateDirectory($backupDirectory)|Out-Null
   $key=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($plan.Path))).Substring(0,16)
   $hash=(Get-FileHash -LiteralPath $plan.Path).Hash.Substring(0,16)
   $plan.Backup=Join-Path $backupDirectory ('hold-v2-'+$key+'-'+$hash+'.ini')
   if(-not (Test-Path -LiteralPath $plan.Backup)){[IO.File]::Copy($plan.Path,$plan.Backup,$false)}
   $plan.Temp=$plan.Path+'.camera-'+[Guid]::NewGuid().ToString('N')+'.tmp'
   [IO.File]::WriteAllText($plan.Temp,$plan.Updated,$plan.Encoding)
  }
  foreach($plan in $plans){
   # A running game or external editor must not overwrite a concurrently changed profile.
   if([IO.File]::ReadAllText($plan.Path) -cne $plan.Original){throw 'An input file changed while preparing camera controls. Try again after closing the game.'}
   [IO.File]::Move($plan.Temp,$plan.Path,$true);$committed+=,$plan
  }
 }catch{foreach($plan in $committed){[IO.File]::Copy($plan.Backup,$plan.Path,$true)};throw}finally{foreach($plan in $plans){if($plan.Temp -and (Test-Path -LiteralPath $plan.Temp)){[IO.File]::Delete($plan.Temp)}}}
 return [pscustomobject]@{Status='Configured';Message='Camera controls: hold middle mouse to rotate; release to stop. Combat key bindings are preserved.';ChangedFiles=$plans.Count}
}
function Install-CameraControls([string]$GameRoot,[string]$DocumentsRoot=''){
 $dll=Join-Path $GameRoot 'UnrealEngine3/Binaries/Win64/winmm.dll'
 if(-not (Test-Path -LiteralPath $dll) -or (Get-FileHash -LiteralPath $dll).Hash -ine '5698BF1BFFCF7BA4EBA8A49083B8CC4BD0A5ABDDEC965537CDC642AAC3CDA5B0'){return}
 $docs=if($DocumentsRoot){$DocumentsRoot}else{[Environment]::GetFolderPath('MyDocuments')}
 $files=@((Join-Path $GameRoot 'UnrealEngine3/MarvelGame/Config/DefaultInput.ini'),(Join-Path $docs 'My Games/Marvel Heroes/MarvelGame/Config/MarvelInput.ini'),(Join-Path $docs 'My Games/Marvel Heroes/MarvelGame/Config/MarvelInputUserSettings.ini'))
 Set-CameraInputFiles $GameRoot $files
}
function Test-ProtectedClientFile([string]$Root,[string]$Relative,[switch]$AllowExecutableRepair){
 $path=Get-SafePath $Root $Relative
 if(-not(Test-Path -LiteralPath $path)){return $false}
 if($Relative -match '(?i)(^|/)(Config|Saved|SaveGames|Screenshots)(/|$)|\.ini$'){return $true}
 if(-not $AllowExecutableRepair -and $Relative -match '(?i)(^|/)MarvelHeroesOmega\.exe$'){return $true}
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





# Install the appropriate store artwork without replacing other HUD customizations.
function Install-SplinterStoreGraphics([string]$GameRoot) {
 $relative='UnrealEngine3/MarvelGame/CookedPCConsole/MarvelHUD_SF.upk'
 $target=Get-SafePath $GameRoot $relative
 $payloadRoot=Get-SafePath $GameRoot 'MarvelStoreGraphics'
 if(-not (Test-Path -LiteralPath $payloadRoot -PathType Container)){return 'Store artwork update is not installed.'}
 if(-not (Test-Path -LiteralPath $target -PathType Leaf)){return 'Store artwork could not be updated because the HUD file was not found.'}
 $variants=@(
  @{base='35CF451EF2480DD6E66A5F23FA5DFC4B85ABF2D7ED61198A01DD91E9FF0A387B';result='9A18B3D499FBC8492BDFDB1DAFFB54846865EFEC923576645614FC1B84DCE76E';payload='standard.upk'},
  @{base='17D5F7F513212EB5BB2B606C71ABD802E1657357405D824E797C9C1637E76346';result='E1C82403E2F764351E7B26C7EC3CA82D4DD7654B38C2D32A6607E1A81266CF97';payload='wardrobe.upk'}
 )
 $hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
 if(@($variants|Where-Object {$_.result -eq $hash}).Count){return 'Splinter store artwork is ready.'}
 $match=@($variants|Where-Object {$_.base -eq $hash})
 if($match.Count -ne 1){return 'Store artwork was preserved because this HUD contains other custom changes.'}
 $variant=$match[0];$payload=Get-SafePath $payloadRoot $variant.payload;Assert-Hash $payload $variant.result
 $transaction=Get-SafePath $GameRoot ('.mh-updates/transaction-'+[Guid]::NewGuid().ToString('N'))
 $stage=Join-Path $transaction 'stage';$staged=Get-SafePath $stage $relative;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($staged))|Out-Null
 [IO.File]::Copy($payload,$staged,$false)
 Install-Transaction $GameRoot $stage $transaction @([pscustomobject]@{path=$relative;sha256=$variant.result;baseSha256=$variant.base;protectLocal=$true})
 return 'Splinter store artwork is ready.'
}
