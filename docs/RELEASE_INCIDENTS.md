# open890 Release Incidents

## 2026-02-22: v0.1.4 initial release attempt failed
- Tag: `v0.1.4`
- Run ID: `22276364716`
- Result: `build-macos` failed; `publish-release` skipped.
- Symptom: failure during macOS environment setup.

## 2026-02-22: v0.1.5 first attempt cancelled
- Tag: `v0.1.5`
- Run ID: `22276461024`
- Result: `build-ubuntu` and `build-windows` succeeded, `build-macos` cancelled, `publish-release` skipped.
- Explicit error from run summary:
  - `The configuration 'macos-13-us-default' is not supported`
- Initial change that triggered this:
  - workflow pinned to `runs-on: macos-13`.

## Corrective Actions
1. Updated workflow runner to supported label:
   - `runs-on: macos-latest`
2. Set macOS OTP explicitly for compatibility:
   - macOS job `otp-version: '25'`
3. Commit containing CI fix:
   - `3e5b985` (`fix(ci): use supported macOS runner and OTP25 for release build`)
4. Retargeted `v0.1.5` tag to CI-fix commit and reran release.

## Successful Recovery
- Run ID: `22276689959`
- Result: all jobs succeeded, release published.
- Published assets include Windows installer and macOS installer packages.

## Future Prevention
- Do not assume runner labels are allowed on repo/org policy.
- If a job is cancelled in 0 seconds with no steps, suspect runner configuration first.
- Prefer checking run summary via `gh run view <run_id> --repo w9fyi/open890` to capture platform support errors quickly.

## 2026-02-22 to 2026-02-23: Windows installer startup failures and recovery
- Initial user report:
  - Windows installer completed, but app failed to start reliably.
- Key failing smoke runs:
  - `22287493550` (`v0.1.5` installer): non-Windows files present in Windows install root.
  - `22287719972` (`v0.1.6` installer): payload fixed, startup still failed readiness.
  - `22287999648` (`v0.1.7` pre-fix test path): traced logs showed release script resolved `RELEASE_ROOT` to runner drive because batch script used `cd` without `/d`.
- Root causes:
  1. Windows installer payload included cross-platform launchers.
  2. Generated `bin/open890.bat` drive switch bug (`cd "%~dp0\.."` on different drive).
- Corrective actions:
  1. Excluded non-Windows launchers at installer packaging layer and cleaned stale files during install.
  2. Added Windows smoke checks for unexpected cross-platform files.
  3. Added deterministic smoke diagnostics (startup stdout/stderr, probe log, metadata, script snapshots).
  4. Patched release workflow to rewrite `bin/open890.bat` to:
     - `cd /d "%~dp0\.."`
  5. Added smoke assertion requiring `cd /d` line in installed script.
- Successful recovery:
  - Release run `22288148252` (`v0.1.7`) completed successfully.
  - Smoke run `22288377628` against `open890-v0.1.7-setup.exe` passed end-to-end.

## 2026-02-23: First post-release field issue triage (`v0.1.7`)
- Issue opened:
  - `#1` "open890web failure to launch"
  - https://github.com/w9fyi/open890/issues/1
- Reporter symptom:
  - batch window opens, browser opens, no local connection.
- Triage action taken:
  - Requested installer version, launch path used, and script-line verification.
  - Asked for diagnostics bundle/setup log attachment.
  - Triage comment:
    - https://github.com/w9fyi/open890/issues/1#issuecomment-3942030849
- Notes:
  - Keep issue triage linked here so future sessions can quickly reconstruct post-release support history.

## 2026-02-25: `open890-launcher.ps1` cmd.exe quoting bug (`v0.1.8`)
- Root cause identified from Issue #1:
  - `open890-launcher.ps1` used `Start-Process -FilePath "cmd.exe" -ArgumentList "/c $startCommand"` where `$startCommand` began and ended with `"`.
  - Windows `cmd.exe /c` applies a quote-stripping rule when the remainder starts with `"`: it strips the first `"` and the last `"` in the entire string. With a path containing spaces (the default `C:\Program Files\open890`), this left the executable path unquoted — Windows tried to run `C:\Program` (which doesn't exist) and the Erlang server never started.
  - The CI smoke test happened to already use the correct pattern (array `ArgumentList` with outer-quote wrapping on the command), so the smoke passed while the field install failed.
  - Same bug also present in `cmd.exe /c` invocation inside `New-Open890DiagnosticsBundle` (pid check).
- Corrective actions:
  1. Server start: changed to `Start-Process -FilePath $env:ComSpec -ArgumentList @("/d", "/c", $startCommand)` with `$startCommand` wrapped in an extra outer pair of `"` (matching smoke test pattern).
  2. Pid check: changed to `& $env:ComSpec /d /c $pidCmd` with same outer-quote wrapping.
  3. Diagnostics bundle: added collection of Erlang release log directory (`$RootDir\log\`).
- Released as `v0.1.8`.
