param(
  [string]$RootDir = ".",
  [string]$Url = "http://localhost:4000",
  [int]$TimeoutSeconds = 45
)

$ErrorActionPreference = "SilentlyContinue"
$serverLog = Join-Path $env:TEMP "open890-server.log"

function Test-Open890Ready {
  param([string]$Endpoint)
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $Endpoint -TimeoutSec 2
    return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500)
  } catch {
    return $false
  }
}

$ready = Test-Open890Ready -Endpoint $Url

if (-not $ready) {
  $startCommand = "`"$RootDir\bin\open890.bat`" start > `"$serverLog`" 2>&1"
  Start-Process -FilePath "cmd.exe" -ArgumentList "/c $startCommand" -WindowStyle Minimized
}

for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
  if (Test-Open890Ready -Endpoint $Url) {
    $ready = $true
    break
  }
  Start-Sleep -Seconds 1
}

Start-Process $Url

Add-Type -AssemblyName PresentationFramework

if ($ready) {
  [void][System.Windows.MessageBox]::Show(
    "open890 is active.`n`nYour browser will open at $Url",
    "open890"
  )
} else {
  [void][System.Windows.MessageBox]::Show(
    "open890 is starting.`n`nPlease open your browser to $Url if it does not open automatically.",
    "open890"
  )
}

exit 0
