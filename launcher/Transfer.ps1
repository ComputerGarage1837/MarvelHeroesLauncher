function Set-TransferStatus([string]$Message,[long]$Done=0,[long]$Total=0){
 $percent=if($Total -gt 0){[math]::Min(100,[math]::Floor(100.0*$Done/$Total))}else{-1}
 try{Write-JsonAtomic @{message=$Message;done=$Done;total=$Total;percent=$percent} (Join-Path $script:ProgressRoot '.updates/progress.json')}catch{ } # Progress is cosmetic; never abort an installation for a display refresh.
}
function Receive-Asset([string]$Url,[string]$Path,[string]$Hash){
 if(Test-Path -LiteralPath $Path){try{Assert-Hash $Path $Hash;return}catch{}}
 $part=$Path+'.part';$offset=if(Test-Path -LiteralPath $part){(Get-Item -LiteralPath $part).Length}else{0}
 $http=[Net.Http.HttpClient]::new();$http.Timeout=[TimeSpan]::FromHours(12)
 $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,$Url)
 if($offset){$request.Headers.Range=[Net.Http.Headers.RangeHeaderValue]::new($offset,$null)}
 $response=$null;$inputStream=$null;$outputStream=$null
 try {
  $response=$http.SendAsync($request,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
  if([int]$response.StatusCode -eq 416){Remove-Item -LiteralPath $part -Force;throw 'Download cache reset. Please retry the update.'}
  $response.EnsureSuccessStatusCode()|Out-Null
  if([int]$response.StatusCode -ne 206){$offset=0}
  $total=if($null -ne $response.Content.Headers.ContentLength){[long]$response.Content.Headers.ContentLength+$offset}else{0}
  $mode=if($offset){[IO.FileMode]::Append}else{[IO.FileMode]::Create}
  $outputStream=[IO.File]::Open($part,$mode,[IO.FileAccess]::Write,[IO.FileShare]::None)
  $inputStream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
  $buffer=[byte[]]::new(1048576);$done=$offset;$watch=[Diagnostics.Stopwatch]::StartNew()
  while(($read=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0){
   $outputStream.Write($buffer,0,$read);$done+=$read
   if($watch.ElapsedMilliseconds -gt 250){Set-TransferStatus 'Downloading update' $done $total;$watch.Restart()}
  }
  $outputStream.Dispose();$outputStream=$null
  Set-TransferStatus 'Verifying download' $done $total
  Assert-Hash $part $Hash
  [IO.File]::Move($part,$Path,$true)
 } finally {if($inputStream){$inputStream.Dispose()};if($outputStream){$outputStream.Dispose()};if($response){$response.Dispose()};$request.Dispose();$http.Dispose()}
}

