param([switch]$ValidateOnly)
$ErrorActionPreference='Stop'
$settings=Get-Content (Join-Path $PSScriptRoot 'LauncherSettings.json') -Raw|ConvertFrom-Json
$parts=([string]$settings.Resolution).Split('|')[0].Trim().Split('x').Trim()
if($parts.Count -ne 2){throw 'Invalid resolution.'}
$width=[int]$parts[0];$height=[int]$parts[1]
if($width -lt 640 -or $width -gt 16384 -or $height -lt 480 -or $height -gt 8640){throw 'Invalid resolution.'}
$mode=[string]$settings.Mode;if($mode -notin @('Windowed','Fullscreen')){throw 'Invalid display mode.'}
$clientArgs="-robocopy -nosteam -siteconfigurl=myfamilyflix.duckdns.org/SiteConfig.xml -ResX=$width -ResY=$height -$mode"
if($ValidateOnly){Write-Output $clientArgs;exit 0}
if(Get-Process MarvelHeroesOmega -ErrorAction SilentlyContinue){throw 'The game is already running.'}
$folder=if($settings.PSObject.Properties['ClientPath'] -and $settings.ClientPath){$settings.ClientPath}else{Join-Path $PSScriptRoot 'Client'}
$exe=Get-ChildItem -LiteralPath $folder -Filter MarvelHeroesOmega.exe -Recurse -File|Where-Object {$_.FullName -match '\\Win64\\' -and $_.FullName -notmatch '\\.mh-updates\\'}|Select-Object -First 1
if(-not $exe){throw 'Game client not found. Choose Locate Game or Install Game.'}
$guard=$null
try{
 $lockPath=Join-Path $folder '.mh-updates/update.lock'
 if(Test-Path -LiteralPath $lockPath){$guard=[IO.File]::Open($lockPath,'Open','Read','None')}
 Write-Output 'Starting Marvel Heroes Omega...'
 $game=Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -ArgumentList $clientArgs -PassThru
 for($i=0;$i -lt 240;$i++){
  Start-Sleep -Milliseconds 500;$game.Refresh()
  if($game.HasExited){throw 'The game closed before its window appeared.'}
  if($game.MainWindowHandle -ne [IntPtr]::Zero){Write-Output 'Game is open.';exit 0}
 }
 throw 'The game is still starting. The launcher will stay open; check the game window.'
}finally{if($guard){$guard.Dispose()}}
