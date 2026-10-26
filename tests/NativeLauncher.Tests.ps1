$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../launcher/UpdateCore.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('Marvel native test '+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
try{
 $exe=Ensure-NativeLauncher $root
 $bytes=[IO.File]::ReadAllBytes($exe);$pe=[BitConverter]::ToInt32($bytes,60)
 if([BitConverter]::ToUInt16($bytes,$pe+24+68) -ne 2){throw 'Bootstrap is not a Windows GUI executable'}
 @'
param([switch]$ValidateOnly,[string]$Probe)
Add-Type -TypeDefinition 'public class NativeProbe {[System.Runtime.InteropServices.DllImport("kernel32.dll")]public static extern System.IntPtr GetConsoleWindow();}'
@{Probe=$Probe;NoConsole=([NativeProbe]::GetConsoleWindow() -eq [IntPtr]::Zero)}|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot 'result.json')
'@|Set-Content (Join-Path $root 'Play.ps1')
 $expected='folder with spaces\and "quotes"\'
 # Exercise the executable through a path containing spaces and argument quoting.
 & $exe -ValidateOnly -Probe $expected
 $deadline=[DateTime]::UtcNow.AddSeconds(20)
 while(-not (Test-Path (Join-Path $root 'result.json'))){if([DateTime]::UtcNow -gt $deadline){throw 'Native startup timed out'};Start-Sleep -Milliseconds 100}
 $result=Get-Content (Join-Path $root 'result.json') -Raw|ConvertFrom-Json
 if(-not $result.NoConsole -or $result.Probe -cne $expected){throw 'Native startup attached a console or changed arguments'}
 $deadline=[DateTime]::UtcNow.AddSeconds(10)
 while(@(Get-Process MarvelHeroesLauncher -ErrorAction SilentlyContinue|Where-Object Path -eq $exe).Count){if([DateTime]::UtcNow -gt $deadline){throw 'Validation bootstrap did not exit'};Start-Sleep -Milliseconds 100}
 Write-Output 'PASS: GUI executable starts PowerShell without a console and preserves quoted arguments.'
}finally{if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}}
