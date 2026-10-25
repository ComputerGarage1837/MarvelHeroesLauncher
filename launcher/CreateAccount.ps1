param([switch]$ValidateOnly, [string]$PreviewPath,[switch]$ConnectionHelp,[string]$Server)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'UpdateCore.ps1')
Set-StrictMode -Off
$Server='Live'
$profile=Get-ServerProfile $Server
if($ConnectionHelp){
 $help=[Windows.Forms.Form]::new();$help.Text='Server connection and login help';$help.ClientSize=[Drawing.Size]::new(650,570);$help.StartPosition='CenterScreen';$help.FormBorderStyle='FixedDialog';$help.MaximizeBox=$false;$help.BackColor=[Drawing.Color]::Black;$help.ForeColor=[Drawing.Color]::WhiteSmoke;$help.Font=[Drawing.Font]::new('Segoe UI',11)
 $heading=[Windows.Forms.Label]::new();$heading.Text='CONNECTION AND LOGIN HELP';$heading.Font=[Drawing.Font]::new('Segoe UI',19,[Drawing.FontStyle]::Bold);$heading.ForeColor=[Drawing.Color]::FromArgb(212,175,98);$heading.SetBounds(24,20,600,38);$help.Controls.Add($heading)
 $health=[Windows.Forms.TextBox]::new();$health.Multiline=$true;$health.ReadOnly=$true;$health.ScrollBars='Vertical';$health.BackColor=[Drawing.Color]::Black;$health.ForeColor=[Drawing.Color]::WhiteSmoke;$health.Text='Checking configuration, login service, and game connection...';$health.SetBounds(24,80,600,172);$help.Controls.Add($health)
 $hint=[Windows.Forms.Label]::new();$hint.Text='Choose the login message or code shown inside the game:';$hint.SetBounds(24,267,600,28);$help.Controls.Add($hint)
 $reason=[Windows.Forms.ComboBox]::new();$reason.DropDownStyle='DropDownList';$reason.SetBounds(24,302,600,32);$help.Controls.Add($reason)
 $reasons=@(@{text='General login / connection failure';code=0},@{text='Incorrect email or password (401 / 403)';code=401},@{text='Account banned (402)';code=402},@{text='Email not verified (405)';code=405},@{text='Terms need accepting (407)';code=407},@{text='Client update required (409)';code=409},@{text='Account archived (411)';code=411},@{text='Password expired (412)';code=412},@{text='Age restriction (417)';code=417},@{text='Login service error (500)';code=500},@{text='Temporarily unavailable (503)';code=503},@{text='Login accepted, but cannot enter game (200)';code=200})
 foreach($item in $reasons){$null=$reason.Items.Add($item.text)}
 $explanation=[Windows.Forms.Label]::new();$explanation.SetBounds(24,350,600,90);$explanation.ForeColor=[Drawing.Color]::Silver;$help.Controls.Add($explanation)
 $reason.Add_SelectedIndexChanged({$explanation.Text=Get-LoginFailureMessage $reasons[$reason.SelectedIndex].code});$reason.SelectedIndex=0
 $retry=[Windows.Forms.Button]::new();$retry.Text='Check again';$retry.SetBounds(24,490,180,36);$help.Controls.Add($retry)
 $register=[Windows.Forms.Button]::new();$register.Text='Create account';$register.SetBounds(220,490,180,36);$help.Controls.Add($register)
 $register.Add_Click({Start-Process (Get-Process -Id $PID).Path -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -Server {1}' -f $PSCommandPath,$Server) -WindowStyle Hidden})
 $probeState=@{shell=$null;pending=$null};$probeTimer=[Windows.Forms.Timer]::new();$probeTimer.Interval=200
 function Start-Probe {
  $retry.Enabled=$false;$health.Text='Checking configuration, login service, and game connection...'
  $probeState.shell=[powershell]::Create();$null=$probeState.shell.AddScript('param($core,$server) . $core; Test-MarvelConnection -Profile $server').AddArgument((Join-Path $PSScriptRoot 'UpdateCore.ps1')).AddArgument($Server);$probeState.pending=$probeState.shell.BeginInvoke();$probeTimer.Start()
 }
 $retry.Add_Click({Start-Probe})
 $probeTimer.Add_Tick({
  if(-not $probeState.pending.IsCompleted){return};$probeTimer.Stop()
  try{$report=@($probeState.shell.EndInvoke($probeState.pending))[0];if(-not $report){throw 'Empty connection report'};$summary=if($report.Reachable){'Server reachable. Credentials are checked when you sign in inside the game.'}else{'A connection needs attention:'};$health.Text=$summary+"`r`n`r`n"+(($report.Checks|ForEach-Object {"$($_.Name): $($_.Message)"}) -join "`r`n")+"`r`nChecked at "+$report.CheckedAt}catch{$health.Text='The connection check could not finish. Check your internet connection, then try again.'}finally{$probeState.shell.Dispose();$probeState.shell=$null;$retry.Enabled=$true}
 })
 $help.Add_FormClosed({$probeTimer.Stop();if($probeState.shell){$probeState.shell.Stop();$probeState.shell.Dispose()}})
 $help.Text=$profile.Name+' — Connection and login help'
 if($ValidateOnly){if($PreviewPath){Export-FormPreview $help $PreviewPath};Write-Output ('Connection help validated for '+$profile.Name)}else{$help.Add_Shown({Start-Probe});[void]$help.ShowDialog()}
 $probeTimer.Dispose();$help.Dispose();exit 0
}
$endpoint=$profile.Registration
$form=[System.Windows.Forms.Form]::new()
$form.Text='Marvel Heroes — '+$profile.Name+' — Create Account'
$form.ClientSize=[System.Drawing.Size]::new(500,510)
$form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedDialog'; $form.MaximizeBox=$false
$form.AutoScaleMode='Dpi'; $form.Font=[System.Drawing.Font]::new('Segoe UI',10)
$form.BackColor=[System.Drawing.Color]::FromArgb(17,18,22); $form.ForeColor=[System.Drawing.Color]::WhiteSmoke
function Add-Label($text,$y,$height=25){
 $label=[System.Windows.Forms.Label]::new(); $label.Text=$text; $label.SetBounds(28,$y,444,$height); $form.Controls.Add($label); return $label
}
$title=Add-Label 'CREATE YOUR ACCOUNT' 22 34
$title.Font=[System.Drawing.Font]::new('Segoe UI',18,[System.Drawing.FontStyle]::Bold)
$accountHint='Your regular account and character world.'
$null=Add-Label $accountHint 64
function Add-Field($label,$y,$secret=$false){
 $null=Add-Label $label $y
 $box=[System.Windows.Forms.TextBox]::new(); $box.SetBounds(28,($y+26),444,29)
 $box.UseSystemPasswordChar=$secret; $form.Controls.Add($box); return $box
}
$email=Add-Field 'Email address (used to sign in)' 105; $email.MaxLength=320
$player=Add-Field 'Player name (up to 16 letters or numbers)' 174; $player.MaxLength=16
$password=Add-Field 'Password (3-64 characters)' 243 $true; $password.MaxLength=64
$confirm=Add-Field 'Confirm password' 312 $true; $confirm.MaxLength=64
$status=Add-Label 'Create an account here, then select Play and sign in inside the game.' 386 55
$status.ForeColor=[System.Drawing.Color]::Silver
$submit=[System.Windows.Forms.Button]::new(); $submit.Text='Create Account'; $submit.SetBounds(290,455,182,36)
$submit.BackColor=[System.Drawing.Color]::FromArgb(212,175,98); $submit.ForeColor=[System.Drawing.Color]::Black; $submit.FlatStyle='Flat'; $form.Controls.Add($submit)
$form.AcceptButton=$submit
$handler=[System.Net.Http.HttpClientHandler]::new(); $handler.AllowAutoRedirect=$false
$client=[System.Net.Http.HttpClient]::new($handler); $client.Timeout=[TimeSpan]::FromSeconds(20)
$state=@{Task=$null; Body=$null; ReadTask=$null; Response=$null; Created=$false}
$timer=[System.Windows.Forms.Timer]::new(); $timer.Interval=150
$messages=@{
 1='Account creation failed. Check your details and try again.'
 2='The server could not save the account. Please try again later.'
 3='Enter a valid email address.'
 4='That email already has an account. Sign in with it instead.'
 6='Choose a valid player name: up to 16 letters or numbers.'
 7='That player name is already taken. Choose another.'
 8='Your password must contain 3-64 characters.'
}
$submit.Add_Click({
 if($state.Created){$form.Close(); return}
 $address=$email.Text.Trim().ToLowerInvariant(); $name=$player.Text.Trim()
 if($address -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$'){$status.Text='Enter a valid email address.'; return}
 if($name -notmatch '^[A-Za-z0-9]{1,16}$'){$status.Text='Use 1-16 letters or numbers for your player name.'; return}
 if([string]::IsNullOrWhiteSpace($password.Text) -or $password.Text.Length -lt 3){$status.Text='Enter a password of 3-64 characters.'; return}
 if($password.Text -cne $confirm.Text){$status.Text='The passwords do not match.'; return}
 try {
  $body=@{Email=$address; PlayerName=$name; Password=$password.Text}|ConvertTo-Json -Compress
  $state.Body=[System.Net.Http.StringContent]::new($body,[System.Text.Encoding]::UTF8,'application/json'); $body=$null
  $state.Task=$client.PostAsync($endpoint,$state.Body)
  foreach($control in @($email,$player,$password,$confirm,$submit)){$control.Enabled=$false}
  $status.Text='Creating your account...'; $timer.Start()
 } catch { $status.Text='Could not connect securely. Please try again.'; if($state.Body){$state.Body.Dispose();$state.Body=$null} }
})
$timer.Add_Tick({
 if(-not $state.Task.IsCompleted){return}
 try {
  if(-not $state.Response){
   $state.Response=$state.Task.GetAwaiter().GetResult()
   if(-not $state.Response.IsSuccessStatusCode){$statusCode=[int]$state.Response.StatusCode;throw "Registration service returned $statusCode"}
   $state.ReadTask=$state.Response.Content.ReadAsStringAsync()
  }
  if(-not $state.ReadTask.IsCompleted){return}
  $result=$state.ReadTask.GetAwaiter().GetResult()|ConvertFrom-Json
  if($null -eq $result.Result){throw 'Invalid response'}
  $code=[int]$result.Result
  if($code -eq 0){
   $state.Created=$true; $password.Clear(); $confirm.Clear()
   $status.Text='Account created! Close this window, select Play, then sign in with your email and password.'
   $submit.Text='Done'
  } elseif($messages.ContainsKey($code)){$status.Text=$messages[$code]}
  else{$status.Text='The server could not create your account. Please try again.'}
 } catch {
  if($state.Response -and [int]$state.Response.StatusCode -ge 500){$status.Text='The account service is unavailable. Wait a moment, then retry.'}
  elseif($state.Response -and -not $state.Response.IsSuccessStatusCode){$status.Text='The account service rejected the request. Open Login help and check the connection; contact the server owner if it continues.'}
  else{$status.Text='Could not confirm account creation. Open Login help to check the connection. If the email is already registered, sign in instead.'}
 }
 $timer.Stop()
 foreach($control in @($email,$player,$password,$confirm)){$control.Enabled=-not $state.Created}
 $submit.Enabled=$true
 if($state.Response){$state.Response.Dispose()}; if($state.Body){$state.Body.Dispose()}
 $state.Task=$null; $state.Body=$null; $state.Response=$null; $state.ReadTask=$null
})
$form.Add_FormClosed({$timer.Stop(); $client.CancelPendingRequests(); $password.Clear(); $confirm.Clear()})
if($ValidateOnly){
 if($endpoint -notlike 'https://*'){throw 'Registration must use HTTPS'}
 if(-not $password.UseSystemPasswordChar -or -not $confirm.UseSystemPasswordChar){throw 'Password fields must be masked'}
 if($PreviewPath){$form.ShowInTaskbar=$false;$form.StartPosition='Manual';$form.Location=[System.Drawing.Point]::new(-32000,-32000);$form.Show();[System.Windows.Forms.Application]::DoEvents();$bitmap=[System.Drawing.Bitmap]::new($form.Width,$form.Height);$form.DrawToBitmap($bitmap,[System.Drawing.Rectangle]::new(0,0,$form.Width,$form.Height));$bitmap.Save($PreviewPath);$bitmap.Dispose()}
 Write-Output 'Account form validated: masked passwords, HTTPS, no password persistence.'
} else {[void]$form.ShowDialog()}
$timer.Dispose(); $client.Dispose(); $form.Dispose()


