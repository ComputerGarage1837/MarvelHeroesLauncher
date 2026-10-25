param([switch]$ValidateOnly, [string]$PreviewPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
[System.Windows.Forms.Application]::EnableVisualStyles()
$endpoint='https://myfamilyflix.duckdns.org/marvel/accounts/create'
$form=[System.Windows.Forms.Form]::new()
$form.Text='Marvel Heroes - Create Account'
$form.ClientSize=[System.Drawing.Size]::new(500,510)
$form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedDialog'; $form.MaximizeBox=$false
$form.AutoScaleMode='Dpi'; $form.Font=[System.Drawing.Font]::new('Segoe UI',10)
$form.BackColor=[System.Drawing.Color]::FromArgb(17,18,22); $form.ForeColor=[System.Drawing.Color]::WhiteSmoke
function Add-Label($text,$y,$height=25){
 $label=[System.Windows.Forms.Label]::new(); $label.Text=$text; $label.SetBounds(28,$y,444,$height); $form.Controls.Add($label); return $label
}
$title=Add-Label 'CREATE YOUR ACCOUNT' 22 34
$title.Font=[System.Drawing.Font]::new('Segoe UI',18,[System.Drawing.FontStyle]::Bold)
$null=Add-Label 'Server: myfamilyflix.duckdns.org' 64
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
   if(-not $state.Response.IsSuccessStatusCode){throw 'Server request failed'}
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
 } catch { $status.Text='Could not confirm account creation. Retry; if the email is already registered, try signing in.' }
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


