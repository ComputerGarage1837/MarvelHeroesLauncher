$ErrorActionPreference='Stop'
Write-Host 'Marvel Heroes camera diagnostic'
$game=Get-Process MarvelHeroesOmega -ErrorAction SilentlyContinue | Select-Object -First 1
if(-not $game){Write-Host 'GAME: not running. Start the game through the launcher and run this again.';exit 1}
try {$exe=$game.Path;if(-not $exe){throw 'Game path unavailable'};$root=[IO.Path]::GetFullPath((Join-Path (Split-Path $exe) '../../..'))}catch{Write-Host 'GAME: running, but its installation path cannot be read.';exit 1}
$dll=Join-Path $root 'UnrealEngine3/Binaries/Win64/winmm.dll';$upk=Join-Path $root 'UnrealEngine3/MarvelGame/CookedPCConsole/MarvelGame.upk';$sip=Join-Path $root 'Data/Game/Calligraphy.sip'
Write-Host "GAME: running"
foreach($item in @(@{name='Camera loader';path=$dll;hash='5698BF1BFFCF7BA4EBA8A49083B8CC4BD0A5ABDDEC965537CDC642AAC3CDA5B0'},@{name='Camera game file';path=$upk;hash='D130440FE8FBBDD80EC35EE6D53125909BE892132F3D99E4E3CE58FE25967135'},@{name='Camera settings data';path=$sip;hash='8064737DA039B0BBBE25D9A65A2DC3C321F6D60D7F8D4B0664335F5345918F1E'})){
 if(-not(Test-Path -LiteralPath $item.path)){Write-Host "$($item.name): missing";continue}
 $hash=(Get-FileHash -LiteralPath $item.path).Hash
 if($hash -eq $item.hash){Write-Host "$($item.name): correct"}else{Write-Host "$($item.name): different from expected"}
}
try{$mods=@($game.Modules|Where-Object {$_.ModuleName -ieq 'winmm.dll'});$local=@($mods|Where-Object {$_.FileName -ieq $dll});if($local.Count){Write-Host 'Camera loader in game: loaded'}elseif($mods.Count){Write-Host 'Camera loader in game: Windows version loaded instead'}else{Write-Host 'Camera loader in game: not found'}}catch{Write-Host 'Camera loader in game: could not inspect'}
try {
 Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class MHCameraControllerCheck { [DllImport("xinput1_4.dll")] public static extern uint XInputGetState(uint index, IntPtr state); }'
 $buffer=[Runtime.InteropServices.Marshal]::AllocHGlobal(64);try{$connected=@();foreach($i in 0..3){if([MHCameraControllerCheck]::XInputGetState($i,$buffer) -eq 0){$connected+=$i}};Write-Host "XInput controllers detected: $($connected.Count)"}finally{[Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)}
} catch {Write-Host 'XInput controller check: unavailable'}
$docs=[Environment]::GetFolderPath('MyDocuments')
$inputs=@(@{name='Game default';path=(Join-Path $root 'UnrealEngine3/MarvelGame/Config/DefaultInput.ini')},@{name='Player input';path=(Join-Path $docs 'My Games/Marvel Heroes/MarvelGame/Config/MarvelInput.ini')},@{name='Player input settings';path=(Join-Path $docs 'My Games/Marvel Heroes/MarvelGame/Config/MarvelInputUserSettings.ini')})
foreach($inputFile in $inputs){if(-not(Test-Path -LiteralPath $inputFile.path)){Write-Host "$($inputFile.name): not present";continue};$s=Get-Content -LiteralPath $inputFile.path -Raw;$middle=[regex]::Matches($s,'(?im)^\s*[.!+]?Bindings=\(Name="MiddleMouseButton"[^\r\n]*');$ours=@($middle|Where-Object Value -match 'KBM_MMB').Count;$custom=$middle.Count-$ours;$cam=($s -match 'Name="KBM_CamX"') -and ($s -match 'Name="KBM_CamY"');$rb=($s -match 'Name="XboxTypeS_RightShoulder"[^\r\n]*VFXToggleOtherPlayerPowerEffects');$axes=[regex]::Matches($s,'(?im)^\s*[.!+]?Bindings=\(Name="Mouse[XY]"[^\r\n]*');$oursAxes=@($axes|Where-Object Value -match 'KBM_Cam').Count;$otherAxes=$axes.Count-$oursAxes;$mmb=($s -match 'Name="KBM_MMB"[^\r\n]*SetBind MouseX KBM_CamX[^\r\n]*SetBind MouseY KBM_CamY');$axisX=($s -match 'Name="KBM_CamX"[^\r\n]*Axis GamepadRawJoyLookRight');$axisY=($s -match 'Name="KBM_CamY"[^\r\n]*Axis GamepadRawJoyLookUp');Write-Host "$($inputFile.name): mouse=$ours other-middle=$custom camera-aliases=$cam mouse-command=$mmb axis-X=$axisX axis-Y=$axisY controller-RB=$rb active-camera-axes=$oursAxes other-mouse-axes=$otherAxes"}
Write-Host 'Diagnostic complete. Copy the lines above back into the chat.'
