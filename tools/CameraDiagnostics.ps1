param([string]$GameRoot,[string]$DocumentsRoot,[switch]$ObserveInput)
$ErrorActionPreference='Stop'
Write-Host 'Marvel Heroes camera diagnostic'
$game=Get-Process MarvelHeroesOmega -ErrorAction SilentlyContinue | Select-Object -First 1
if(-not $game -and -not $GameRoot){Write-Host 'GAME: not running. Start the game through the launcher and run this again.';exit 1}
try {if($GameRoot){$root=[IO.Path]::GetFullPath($GameRoot)}else{$exe=$game.Path;if(-not $exe){throw 'Game path unavailable'};$root=[IO.Path]::GetFullPath((Join-Path (Split-Path $exe) '../../..'))}}catch{Write-Host 'GAME: running, but its installation path cannot be read.';exit 1}
$dll=Join-Path $root 'UnrealEngine3/Binaries/Win64/winmm.dll';$upk=Join-Path $root 'UnrealEngine3/MarvelGame/CookedPCConsole/MarvelGame.upk';$sip=Join-Path $root 'Data/Game/Calligraphy.sip'
Write-Host ('GAME: '+$(if($game){'running'}else{'offline file inspection; execution is not tested'}))
foreach($item in @(@{name='Camera loader';path=$dll;hash='5698BF1BFFCF7BA4EBA8A49083B8CC4BD0A5ABDDEC965537CDC642AAC3CDA5B0'},@{name='Camera game file';path=$upk;hash='D130440FE8FBBDD80EC35EE6D53125909BE892132F3D99E4E3CE58FE25967135'},@{name='Camera settings data';path=$sip;hash='8064737DA039B0BBBE25D9A65A2DC3C321F6D60D7F8D4B0664335F5345918F1E'})){
 if(-not(Test-Path -LiteralPath $item.path)){Write-Host "$($item.name): missing";continue}
 $hash=(Get-FileHash -LiteralPath $item.path).Hash
 if($hash -eq $item.hash -or ($item.name -eq 'Camera game file' -and $hash -in @('8AA1B3A5FB27B2F096F0B7D6F2BA9DE9F38D1C78EEFD797F3DB8E30FB4A195DB','FE909EBE610B12857D6EA82325B3AE211DFB611E352EC0B59F0661A334436799'))){Write-Host "$($item.name): correct"}else{Write-Host "$($item.name): different from expected"}
}
try{$mods=@($game.Modules|Where-Object {$_.ModuleName -ieq 'winmm.dll'});$local=@($mods|Where-Object {$_.FileName -ieq $dll});if($local.Count){Write-Host 'Camera loader in game: loaded'}elseif($mods.Count){Write-Host 'Camera loader in game: Windows version loaded instead'}else{Write-Host 'Camera loader in game: not found'}}catch{Write-Host 'Camera loader in game: could not inspect'}
try {
 Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class MHCameraControllerCheck { [DllImport("xinput1_4.dll")] public static extern uint XInputGetState(uint index, IntPtr state); }'
 $buffer=[Runtime.InteropServices.Marshal]::AllocHGlobal(64);try{$connected=@();foreach($i in 0..3){if([MHCameraControllerCheck]::XInputGetState($i,$buffer) -eq 0){$connected+=$i}};Write-Host "XInput controllers detected: $($connected.Count)"}finally{[Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)}
} catch {Write-Host 'XInput controller check: unavailable'}
$docs=if($DocumentsRoot){$DocumentsRoot}else{[Environment]::GetFolderPath('MyDocuments')}
$inputs=@(@{name='Game default';path=(Join-Path $root 'UnrealEngine3/MarvelGame/Config/DefaultInput.ini')},@{name='Player input';path=(Join-Path $docs 'My Games/Marvel Heroes/MarvelGame/Config/MarvelInput.ini')},@{name='Player input settings';path=(Join-Path $docs 'My Games/Marvel Heroes/MarvelGame/Config/MarvelInputUserSettings.ini')})
foreach($inputFile in $inputs){if(-not(Test-Path -LiteralPath $inputFile.path)){Write-Host "$($inputFile.name): not present";continue};$s=Get-Content -LiteralPath $inputFile.path -Raw;$middle=[regex]::Matches($s,'(?im)^\s*[.!+]?Bindings=\(Name="MiddleMouseButton"[^\r\n]*');$ours=@($middle|Where-Object Value -match 'KBM_MMB').Count;$custom=$middle.Count-$ours;$cam=($s -match 'Name="KBM_CamX"') -and ($s -match 'Name="KBM_CamY"');$rb=($s -match 'Name="XboxTypeS_RightShoulder"[^\r\n]*VFXToggleOtherPlayerPowerEffects');$axes=[regex]::Matches($s,'(?im)^\s*[.!+]?Bindings=\(Name="Mouse[XY]"[^\r\n]*');$oursAxes=@($axes|Where-Object Value -match 'KBM_Cam').Count;$otherAxes=$axes.Count-$oursAxes;$mmb=($s -match 'Name="KBM_MMB"[^\r\n]*SetBind MouseX KBM_CamX[^\r\n]*SetBind MouseY KBM_CamY');$axisX=($s -match 'Name="KBM_CamX"[^\r\n]*Axis GamepadRawJoyLookRight');$axisY=($s -match 'Name="KBM_CamY"[^\r\n]*Axis GamepadRawJoyLookUp');Write-Host "$($inputFile.name): mouse=$ours other-middle=$custom camera-aliases=$cam mouse-command=$mmb axis-X=$axisX axis-Y=$axisY controller-RB=$rb active-camera-axes=$oursAxes other-mouse-axes=$otherAxes"}
foreach($inputFile in $inputs){
 if(-not(Test-Path -LiteralPath $inputFile.path)){continue}
 $content=Get-Content -LiteralPath $inputFile.path -Raw
 $matchesF7=[regex]::Matches($content,'(?im)^\s*[.!+]?Bindings=\(Name="F7"[^\r\n]*')
 $cameraF7=@($matchesF7|Where-Object Value -match 'Command="KBM_Toggle(On|Off)"').Count
 $otherF7=$matchesF7.Count-$cameraF7
 $toggleOn=$content -match 'Name="KBM_ToggleOn"[^\r\n]*SetBind MouseX KBM_CamX[^\r\n]*SetBind MouseY KBM_CamY'
 $toggleOff=$content -match 'Name="KBM_ToggleOff"[^\r\n]*SetBind MouseX KBM_None[^\r\n]*SetBind MouseY KBM_None'
 Write-Host "$($inputFile.name) F7: camera=$cameraF7 other=$otherF7 toggle-on=$toggleOn toggle-off=$toggleOff"
}
Write-Host 'SECTION DETAIL (file text only; does not establish runtime execution):'
foreach($inputFile in $inputs){
 if(-not (Test-Path -LiteralPath $inputFile.path)){continue}
 $sections=@{};$section=''
 foreach($line in Get-Content -LiteralPath $inputFile.path){
  if($line -match '^\s*\[([^]]+)\]'){$section=$Matches[1];continue}
  if($line -match '^\s*([.!+\-]?)(Bindings|ControllerBindings)\s*='){
   if(-not $sections.ContainsKey($section)){$sections[$section]=@()}
   $sections[$section]+=,$line.Trim()
  }
 }
 foreach($section in ($sections.Keys|Sort-Object)){
  Write-Host ("$($inputFile.name) [$section]")
  foreach($key in 'Bindings','ControllerBindings'){
   $counts=foreach($prefix in '','.','+','!','-'){$n=@($sections[$section]|Where-Object {$_ -match ('^'+[regex]::Escape($prefix+$key)+'\s*=')}).Count;($prefix+$key+'='+$n)}
   Write-Host ('  '+($counts -join ' '))
  }
  foreach($line in $sections[$section]){
   if($line -match 'Name\s*=\s*"(MiddleMouseButton|MouseX|MouseY|F7|KBM_[^"]+|BackSpace|Backspace|XboxTypeS_RightShoulder)"'){Write-Host ('  '+$line)}
   elseif($line -match '^!Bindings\s*=\s*ClearArray'){Write-Host ('  ARRAY DIRECTIVE: '+$line)}
  }
 }
 $text=Get-Content -LiteralPath $inputFile.path -Raw
 $ui=[regex]::Match($text,'(?ms)^\[Engine\.UIInputConfiguration\][^\r\n]*\r?\n(.*?)(?=^\[|\z)').Groups[1].Value
 $backspace=[regex]::Matches($ui,'(?i)InputAliasName="BackSpace",LinkedInputKeys=\(\(InputKeyName="BackSpace"').Count
 Write-Host ("$($inputFile.name) login UI: BackSpace alias mappings=$backspace (stock default has 2; this does not prove UI execution)")
 foreach($sectionMatch in [regex]::Matches($text,'(?ms)^\s*\[(Scaleform\.KeyMap|Scaleform\.GamepadMouse)\][^\r\n]*\r?\n(.*?)(?=^\[|\z)')){
  Write-Host ("$($inputFile.name) [$($sectionMatch.Groups[1].Value)]")
  foreach($line in $sectionMatch.Groups[2].Value -split '\r?\n'){if($line -match '(?i)back|mouse|gamepad|^[XY]\s*='){Write-Host ('  '+$line.Trim())}}
 }
}
if($ObserveInput -and $game){
 if(-not ('MHCameraInputObservation' -as [type])){Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class MHCameraInputObservation {
 [DllImport("user32.dll")]public static extern short GetAsyncKeyState(int key);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
 [StructLayout(LayoutKind.Sequential)]public struct Point{public int X;public int Y;}
 [DllImport("user32.dll")]public static extern bool GetCursorPos(out Point point);
 public static bool InGame(uint gamePid){uint pid;GetWindowThreadProcessId(GetForegroundWindow(),out pid);return pid==gamePid;}
 public static bool CursorMoved(ref Point old){Point p;GetCursorPos(out p);bool moved=p.X!=old.X||p.Y!=old.Y;old=p;return moved;}
}
'@}
 Write-Host 'For 20 seconds: switch to the game, hold middle mouse and move it, then try Backspace in the login field. Only button states are counted; no text is recorded.'
 $point=[MHCameraInputObservation+Point]::new();$foreground=0;$middle=0;$movement=0;$backspace=0;$until=[DateTime]::UtcNow.AddSeconds(20)
 while([DateTime]::UtcNow -lt $until){
  if([MHCameraInputObservation]::InGame([uint32]$game.Id)){
   $foreground++;$moved=[MHCameraInputObservation]::CursorMoved([ref]$point)
   if(([MHCameraInputObservation]::GetAsyncKeyState(4) -band 0x8000) -ne 0){$middle++;if($moved){$movement++}}
   if(([MHCameraInputObservation]::GetAsyncKeyState(8) -band 0x8000) -ne 0){$backspace++}
  };Start-Sleep -Milliseconds 20
 }
 Write-Host "Windows observation: game-focused samples=$foreground middle-held samples=$middle middle-plus-movement samples=$movement Backspace-down samples=$backspace"
 Write-Host 'This establishes Windows button state only, not whether the game handled an event or rotated the camera.'
}
Write-Host 'Backspace has no plain gameplay binding in the stock game default. A missing Backspace Bindings entry alone is not evidence of broken text input.'
Write-Host 'Do not paste account credentials or the full game command line. Copy the diagnostic lines above back into the chat.'


