@echo off
rem open890 Windows desktop launcher.
rem Starts the Erlang server in a minimized background window, then polls
rem http://localhost:4000 and opens the default browser once the server
rem is ready. No nested cmd /c calls, so paths with spaces (e.g. the
rem default C:\Program Files\open890 install path) are safe.

start "open890" /min "%~dp0bin\open890.bat" start

powershell -NoProfile -Command "$u='http://localhost:4000'; for ($i=0; $i -lt 60; $i++) { try { $r = Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 2; if ($r.StatusCode -lt 500) { Start-Process $u; exit 0 } } catch { Start-Sleep -Seconds 1 } }; Start-Process $u"
