param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][version]$LauncherVersion,[string]$Repository='ComputerGarage1837/MarvelHeroesLauncher')
$ErrorActionPreference='Stop'
if($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'){throw 'Invalid repository.'}
$env:GIT_TERMINAL_PROMPT='0';$env:GCM_INTERACTIVE='Never'
$credential="protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
if($LASTEXITCODE -ne 0){throw 'GitHub credentials are unavailable.'}
$password=@($credential|Where-Object {$_ -like 'password=*'}|Select-Object -First 1)
if($password.Count -ne 1){throw 'GitHub credentials are unavailable.'}
$token=$password[0].Substring(9);$headers=@{'User-Agent'='MarvelHeroes-publisher';Authorization=('Bearer '+$token);Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'}
$base="https://api.github.com/repos/$Repository"
$release=Invoke-RestMethod "$base/releases/tags/client-patches" -Headers $headers
if(-not $release.prerelease -or $release.draft){throw 'The client staging release is not available.'}
try{$existing=Invoke-RestMethod "$base/releases/tags/v$LauncherVersion" -Headers $headers;throw "Release v$LauncherVersion already exists; inspect it before retrying."}catch{if($_.Exception.Response.StatusCode.value__ -ne 404){throw}}
$descriptor=@(Get-ChildItem -LiteralPath $Directory -Filter 'client-full-*.package.json');if($descriptor.Count -ne 1){throw 'Expected exactly one full-client descriptor.'}
$package=Get-Content $descriptor[0].FullName -Raw|ConvertFrom-Json
if($package.component -ne 'client-full' -or @($package.parts).Count -eq 0){throw 'Invalid full-client descriptor.'}
$all=@($package.parts|ForEach-Object {@{name=$_.asset;sha256=$_.sha256;size=[long]$_.size}})
$all+=@{name=$descriptor[0].Name;sha256=(Get-FileHash $descriptor[0].FullName).Hash.ToLowerInvariant();size=$descriptor[0].Length}
$http=[Net.Http.HttpClient]::new();$http.Timeout=[TimeSpan]::FromHours(12)
$http.DefaultRequestHeaders.UserAgent.ParseAdd('MarvelHeroes-publisher');$http.DefaultRequestHeaders.Authorization=[Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$token)
try{
 foreach($item in $all){
  if($item.name -notmatch '^[A-Za-z0-9_.-]+$' -or $item.sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid asset metadata.'}
  $file=Get-Item -LiteralPath (Join-Path $Directory $item.name);if($file.Length -ne $item.size){throw "Wrong asset size: $($item.name)"}
  $prior=@($release.assets|Where-Object name -eq $item.name)
  if($prior.Count -gt 1){throw "Duplicate staging asset: $($item.name)"}
  if($prior.Count -eq 1){if([long]$prior[0].size -ne $item.size -or ($prior[0].digest -and $prior[0].digest -ne ('sha256:'+$item.sha256))){throw "Existing asset differs: $($item.name)"};Write-Output "Already uploaded: $($item.name)";continue}
  Write-Output "Uploading $($item.name) ($($item.size) bytes)"
  $response=$null;$stream=[IO.File]::OpenRead($file.FullName);$content=[Net.Http.StreamContent]::new($stream);$content.Headers.ContentType=[Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
  try{$url=($release.upload_url -split '\{')[0]+'?name='+[uri]::EscapeDataString($item.name);if(-not $url.StartsWith('https://uploads.github.com/')){throw 'Untrusted upload URL.'};$response=$http.PostAsync($url,$content).GetAwaiter().GetResult();if(-not $response.IsSuccessStatusCode){throw "GitHub upload failed with HTTP $([int]$response.StatusCode)."};$result=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json;if([long]$result.size -ne $item.size){throw 'Uploaded asset has an unexpected size.'};if($result.digest -and $result.digest -ne ('sha256:'+$item.sha256)){throw 'Uploaded asset checksum differs.'}}finally{$content.Dispose();$stream.Dispose();if($response){$response.Dispose()}}
 }
 $body=@{ref='main';inputs=@{version="$LauncherVersion"}}|ConvertTo-Json
 Invoke-RestMethod "$base/actions/workflows/release.yml/dispatches" -Headers $headers -Method Post -ContentType 'application/json' -Body $body|Out-Null
 Write-Output "Uploaded all parts and started release v$LauncherVersion. Confirm the workflow succeeds before calling the download available."
}finally{$http.Dispose();$token=$null;$headers=$null}
