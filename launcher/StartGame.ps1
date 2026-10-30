param([switch]$ValidateOnly,[switch]$CheckConnection,[string]$Server)
$ErrorActionPreference='Stop'
try {
. (Join-Path $PSScriptRoot 'UpdateCore.ps1')
$settings=Get-PlayerSettings $PSScriptRoot
$settings.Server='Live'
if($CheckConnection){Test-MarvelConnection -Profile $settings.Server|ConvertTo-Json -Depth 5 -Compress;exit 0}
$profile=Get-ServerProfile $settings.Server
$display=Get-GameDisplay $settings;$width=$display.Width;$height=$display.Height
$mode=[string]$settings.Mode;if($mode -notin @('Windowed','Fullscreen','Borderless')){throw 'Invalid display mode.'}
$borderless=$mode -eq 'Borderless';if($borderless){$mode='Windowed'}
$clientArgs=Get-GameLaunchArguments $settings $display
if($ValidateOnly){Write-Output $clientArgs;Write-Output "Monitor: $($display.Device); borderless: $borderless";exit 0}
$connection=Test-MarvelConnection -Profile $settings.Server
if(-not $connection.Reachable){throw (($connection.Checks|Where-Object {-not $_.Ok}|ForEach-Object {"$($_.Name): $($_.Message)"}) -join ' ')}
if(Get-Process MarvelHeroesOmega -ErrorAction SilentlyContinue){throw 'The game is already running.'}
$folder=$settings.ClientPath
$exe=Get-ChildItem -LiteralPath $folder -Filter MarvelHeroesOmega.exe -Recurse -File|Where-Object {$_.FullName -match '\\Win64\\' -and $_.FullName -notmatch '\\.mh-updates\\'}|Select-Object -First 1
if(-not $exe){throw 'Game client not found. Choose Locate Game or Install Game.'}
$guard=$null
try{
 $lockPath=Join-Path $folder '.mh-updates/update.lock'
 if(Test-Path -LiteralPath $lockPath){$guard=[IO.File]::Open($lockPath,'Open','Read','None')}
 $camera=Install-CameraControls $folder
 if($camera){Write-Output $camera.Message}
 $storeArtwork=Install-SplinterStoreGraphics $folder
 if($storeArtwork){Write-Output $storeArtwork}
 Write-Output 'Starting Marvel Heroes Omega...'
 $game=Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -ArgumentList $clientArgs -PassThru
 for($i=0;$i -lt 240;$i++){
  Start-Sleep -Milliseconds 500;$game.Refresh()
  if($game.HasExited){throw 'The game closed before its window appeared.'}
  if($game.MainWindowHandle -ne [IntPtr]::Zero){
   if($borderless){
    # Wait for the engine to finish its initial window sizing, then apply the native monitor bounds.
    Start-Sleep -Seconds 2;$game.Refresh()
    if($game.HasExited){throw 'The game closed while applying display settings.'}
    [MHDisplay]::Borderless($game.MainWindowHandle,$display.X,$display.Y,$display.Width,$display.Height)
   }
   Write-Output 'Game is open.';exit 0
  }
 }
 throw 'The game is still starting. The launcher will stay open; check the game window.'
}finally{if($guard){$guard.Dispose()}}
}catch{Write-Output $_.Exception.Message;exit 1}

