$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../launcher/UpdateCore.ps1')
function Check($condition,[string]$message){if(-not $condition){throw "FAIL: $message"};Write-Output "PASS: $message"}
$baseline=Get-Content (Join-Path $PSScriptRoot 'fixtures/CameraInput-SavedBindings.ini') -Raw
$baselineLines=@($baseline -split '\r?\n'|Where-Object {$_ -cmatch '^Bindings='})
Check ($baselineLines.Count -eq 80) 'Fixture reproduces the 80 saved bindings in the supplied section diagnostic'
$oldCamera=@(
 '.Bindings=(Name="KBM_CamX",Command="Axis GamepadRawJoyLookRight Speed=0.1667")',
 '.Bindings=(Name="KBM_CamY",Command="Axis GamepadRawJoyLookUp Speed=-0.1667")',
 '.Bindings=(Name="KBM_None",Command="")',
 '.Bindings=(Name="KBM_MMB",Command="SetBind MouseX KBM_CamX | SetBind MouseY KBM_CamY | OnRelease SetBind MouseX KBM_None | OnRelease SetBind MouseY KBM_None")',
 '.Bindings=(Name="MiddleMouseButton",Command="KBM_MMB")',
 '.Bindings=(Name="KBM_ToggleOn",Command="SetBind MouseX KBM_CamX | SetBind MouseY KBM_CamY | SetBind F7 KBM_ToggleOff")',
 '.Bindings=(Name="KBM_ToggleOff",Command="SetBind MouseX KBM_None | SetBind MouseY KBM_None | SetBind F7 KBM_ToggleOn")',
 '.Bindings=(Name="F7",Command="KBM_ToggleOn")')
$ui=@'
[Engine.UIInputConfiguration]
+WidgetInputAliases=(WidgetClassName="Engine.UIEditBox",InputAliasName="BackSpace",InputKeyName="BackSpace")
[Scaleform.KeyMap]
Gamepad_LeftStick_Left=GAMEPAD_LS_Left
[UnrealEd.EditorViewportInput]
+Bindings=(Name="F7",Command="EditorOnly")
'@
$default="[MarvelGame.MarvelInput]`r`n!Bindings=ClearArray`r`n"+((@($baselineLines|ForEach-Object {'.'+$_})+$oldCamera) -join "`r`n")+"`r`n"+$ui
$player="[MarvelGame.MarvelInput]`r`n!Bindings=ClearArray`r`n"+(($baselineLines+@($baselineLines|ForEach-Object {'.'+$_})+$oldCamera) -join "`r`n")+"`r`n"+$ui
$settings="[MarvelGame.MarvelInput]`r`n"+((@($baselineLines|ForEach-Object {'!'+$_})+@($baselineLines|ForEach-Object {'+'+$_})) -join "`r`n")+"`r`n[Untouched]`r`nKeep=custom`r`n"
# Independent reader: select the generated Bindings array, then apply the author's user-settings !/+ diff model.
# This models config resolution only; it does not claim to execute the actual game engine.
function Read-TestBindings([string]$text,[string[]]$prefixes){
 $inSection=$false
 foreach($line in $text -split '\r?\n'){
  if($line -match '^\[([^]]+)\]'){$inSection=$Matches[1] -eq 'MarvelGame.MarvelInput';continue}
  if(-not $inSection -or $line -notmatch '^([.!+\-]?)Bindings=\(Name="([^"]+)",\s*Command="([^"]*)"(.*)\)$'){continue}
  $prefix=$Matches[1];$name=$Matches[2];$command=$Matches[3];$tail=$Matches[4]
  if($prefix -notin $prefixes){continue}
  $mods=foreach($flag in @('Control','Shift','Alt','bIgnoreCtrl','bIgnoreShift','bIgnoreAlt')){$tail -match ('(?:^|,)\s*'+$flag+'=True(?:,|$)')}
  [pscustomobject]@{Prefix=$prefix;Name=$name;Command=$command;Mods=($mods -join ',');Identity=($name+'|'+$command+'|'+($mods -join ','))}
 }
}
function Merge-TestBindings($base,[string]$overlay){
 $result=@($base)
 foreach($entry in @(Read-TestBindings $overlay @('!','+'))){
  if($entry.Prefix -eq '!'){$result=@($result|Where-Object Identity -cne $entry.Identity)}else{$result+=,$entry}
 }
 return $result
}
$before=@(Merge-TestBindings @(Read-TestBindings $player @('')) $settings)
Check (@($before|Where-Object Name -eq MiddleMouseButton).Count -eq 0) 'Reproduces missing middle-mouse camera command in the saved binding layer before repair'
$newDefault=(Update-CameraInputText $default).Text;$newPlayer=(Update-CameraInputText $player).Text;$newSettings=(Update-CameraInputText $settings).Text
foreach($prefix in @('','.')){
 $entries=@(Read-TestBindings $newPlayer @($prefix));Check (@($entries|Where-Object Name -eq MiddleMouseButton).Count -eq 1) "Player $prefix representation contains one middle-mouse binding"
}
foreach($prefix in @('!','+')){Check (@(Read-TestBindings $newSettings @($prefix)|Where-Object Name -eq MiddleMouseButton).Count -eq 1) "Saved user-settings $prefix representation contains middle-mouse binding"}
foreach($mode in @('Saved','Combined')){
 $baseEntries=if($mode -eq 'Saved'){@(Read-TestBindings $newPlayer @(''))}else{@(Read-TestBindings $newPlayer @('','.'))}
 $merged=@(Merge-TestBindings $baseEntries $newSettings)
 Check ($merged.Count -eq 85 -and @($merged|Group-Object Name,Mods|Where-Object Count -gt 1).Count -eq 0) "$mode merge leaves 80 original entries plus five unique camera bindings"
 foreach($old in @(Read-TestBindings $baseline @(''))){Check (@($merged|Where-Object Identity -ceq $old.Identity).Count -eq 1) ("Preserves original "+$old.Name+' '+$old.Mods)}
 $hold=($merged|Where-Object Name -eq KBM_MMB).Command
 Check ($hold -ceq 'SetBind MouseX KBM_CamX | SetBind MouseY KBM_CamY | OnRelease SetBind MouseX KBM_None | OnRelease SetBind MouseY KBM_None') "$mode merge resolves the author's hold-and-release command"
 Check (@($merged|Where-Object Name -match '^F7$|^KBM_Toggle').Count -eq 0) "$mode merge removes the launcher F7 experiment"
}
Check ($newDefault.EndsWith($ui) -and $newPlayer.EndsWith($ui)) 'Login UI aliases, Scaleform mappings and other sections remain byte-for-byte unchanged'
Check ((Update-CameraInputText $newDefault).Text -ceq $newDefault -and (Update-CameraInputText $newPlayer).Text -ceq $newPlayer -and (Update-CameraInputText $newSettings).Text -ceq $newSettings) 'Repeated launches do not duplicate or rewrite controls'
$custom=$baseline+"`r`nBindings=(Name=`"MiddleMouseButton`",Command=`"CustomCombatAction`")`r`n"
Check ((Update-CameraInputText $custom).Text -ceq $custom) 'Custom middle-mouse combat binding prevents automatic replacement'
$axis=$baseline+"`r`nBindings=(Name=`"MouseX`",Command=`"Axis aMouseX`")`r`n"
Check ((Update-CameraInputText $axis).Text -ceq $axis) 'Custom mouse-axis bindings are preserved'
$customF7=$baseline+"`r`nBindings=(Name=`"F7`",Command=`"CustomAction`")`r`n"
Check ((Update-CameraInputText $customF7).Text.Contains('Name="F7",Command="CustomAction"')) 'Custom F7 command survives removal of the launcher experiment'
$controller="[KeyBindings_Classic]`r`n.ControllerBindings=(Name=`"XboxTypeS_RightShoulder`",Command=`"TargetLockOnToggle`")`r`n.ControllerBindings=(Name=`"XboxTypeS_RightShoulder`",Shift=True,Command=`"RevealInteractiblesToggle`")`r`n[Other]`r`n.Bindings=(Name=`"XboxTypeS_RightShoulder`",Command=`"TargetLockOnToggle`")`r`n"
$fixedController=(Update-CameraInputText $controller).Text
Check ($fixedController.Contains('TargetLockOnToggle | VFXToggleOtherPlayerPowerEffects | OnRelease VFXTogglePowerDecals') -and $fixedController.Contains('Shift=True,Command="RevealInteractiblesToggle"') -and $fixedController.EndsWith("[Other]`r`n.Bindings=(Name=`"XboxTypeS_RightShoulder`",Command=`"TargetLockOnToggle`")`r`n")) 'Controller camera extension preserves target lock, modified commands and unrelated sections'
$sandbox=Join-Path $PSScriptRoot ('sandbox-camera-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $sandbox|Out-Null
try{
 $a=Join-Path $sandbox 'Player.ini';$b=Join-Path $sandbox 'UserSettings.ini'
 [IO.File]::WriteAllText($a,$player,[Text.UnicodeEncoding]::new($false,$true));[IO.File]::WriteAllText($b,$settings,[Text.UTF8Encoding]::new($false))
 $hashA=(Get-FileHash $a).Hash;$hashB=(Get-FileHash $b).Hash
 (Get-Item $b).IsReadOnly=$true;$failed=$false;try{Set-CameraInputFiles $sandbox @($a,$b)|Out-Null}catch{$failed=$true}finally{(Get-Item $b).IsReadOnly=$false}
 Check ($failed -and (Get-FileHash $a).Hash -eq $hashA -and (Get-FileHash $b).Hash -eq $hashB) 'Read-only input aborts before any original file is changed'
 $lock=[IO.File]::Open($b,'Open','Read','Read');$failed=$false
 try{Set-CameraInputFiles $sandbox @($a,$b)|Out-Null}catch{$failed=$true}finally{$lock.Dispose()}
 Check ($failed -and (Get-FileHash $a).Hash -eq $hashA -and (Get-FileHash $b).Hash -eq $hashB) 'Locked second file rolls back an already replaced first file'
 $result=Set-CameraInputFiles $sandbox @($a,$b)
 Check ($result.ChangedFiles -eq 2 -and @(Get-ChildItem (Join-Path $sandbox '.mh-camera-control-backups') -Filter '*.ini').Count -eq 2) 'Successful repair backs up both input profiles'
 $bytes=[IO.File]::ReadAllBytes($a);Check ($bytes[0] -eq 255 -and $bytes[1] -eq 254) 'UTF-16 player profile retains its encoding'
 $bytes=[IO.File]::ReadAllBytes($b);Check (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) 'UTF-8 input without a BOM retains its encoding'
 Check ((Set-CameraInputFiles $sandbox @($a,$b)).ChangedFiles -eq 0) 'Repaired files remain unchanged on the next startup'
 $unknown=Join-Path $sandbox 'UnrealEngine3/Binaries/Win64';New-Item -ItemType Directory -Path $unknown -Force|Out-Null;[IO.File]::WriteAllText((Join-Path $unknown 'winmm.dll'),'unknown-loader')
 Check ($null -eq (Install-CameraControls $sandbox)) 'Unrecognized loader never triggers automatic input changes'
}finally{if([IO.Path]::GetFullPath($sandbox).StartsWith([IO.Path]::GetFullPath($PSScriptRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $sandbox -Recurse -Force}}
Write-Output 'Camera configuration tests passed. Runtime camera movement and login editing still require a gaming-PC test.'
