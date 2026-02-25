# open890 Release Runbook

## Purpose
Use this runbook to publish open890 releases with repeatable steps and clear recovery paths when CI fails.

## Prerequisites
- Branch is up to date and pushed.
- Working tree is clean for tracked files.
- Required release workflow secrets are configured (for example `SECRET_KEY_BASE`).
- You have push permission to `w9fyi/open890`.

## Standard Release Flow
1. Ensure tracked working tree is clean:
   - `git status --short`
2. Publish release tag:
   - `./pushrelease vX.Y.Z`
3. Monitor workflow:
   - `https://github.com/w9fyi/open890/actions/workflows/release.yml`
4. Confirm all jobs succeed:
   - `build-ubuntu`
   - `build-windows`
   - `build-macos`
   - `smoke-ubuntu`
   - `smoke-windows`
   - `smoke-macos`
   - `publish-release`
5. Verify release page assets:
   - `open890-vX.Y.Z-setup.exe`
   - `open890-vX.Y.Z-windows-x64.zip`
   - `open890-vX.Y.Z-macos-installer.pkg`
   - `open890-vX.Y.Z-macos.tar.gz`
   - `open890-vX.Y.Z-ubuntu-x64.tar.gz`
   - `open890-FIRST_TIME_SETUP.md`

## Windows Installer Validation (Required)
After a release is published, run the Windows installer smoke workflow against the published `.exe`.

1. Trigger smoke run:
   - `gh workflow run windows-installer-smoke.yml --repo w9fyi/open890 --ref <branch> -f installer_url='https://github.com/w9fyi/open890/releases/download/vX.Y.Z/open890-vX.Y.Z-setup.exe' -f app_url='http://localhost:4000' -f timeout_seconds='90'`
2. Confirm required steps pass:
   - `Verify expected installed files`
   - `Start open890 and wait for readiness`
   - `Start open890 via PS1 launcher (headless)`
   - `Stop open890`
3. If smoke fails, download diagnostics artifact:
   - `gh run download <run_id> --repo w9fyi/open890 -n windows-installer-smoke-diagnostics -D /tmp/open890-smoke-<run_id>`
4. If failure is a real release blocker, ship a new patch release (`vX.Y.(Z+1)`).

## Monitoring Commands
- Latest release workflow runs:
  - `gh run list --repo w9fyi/open890 --workflow release.yml --limit 10`
- Run summary:
  - `gh run view <run_id> --repo w9fyi/open890`
- Jobs only:
  - `gh run view <run_id> --repo w9fyi/open890 --json jobs`

## Tag Guidance
### Preferred
Create a new patch version (`vX.Y.(Z+1)`) for fixes after a failed release.

### Reusing a Tag (if explicitly desired)
Only do this intentionally.
1. Push fix commit first.
2. Delete local tag:
   - `git tag -d vX.Y.Z`
3. Delete remote tag:
   - `git push origin :refs/tags/vX.Y.Z`
4. Recreate annotated tag at current HEAD:
   - `git tag -a vX.Y.Z -m "open890 vX.Y.Z"`
5. Push tag:
   - `git push origin vX.Y.Z`

## macOS Runner Notes (Important)
The workflow failed on 2026-02-22 when using `runs-on: macos-13` with:
- `The configuration 'macos-13-us-default' is not supported`

Current working configuration in `.github/workflows/release.yml`:
- `runs-on: macos-latest`
- macOS beam setup uses `otp-version: '25'`

If macOS is cancelled at 0s again, check runner label support first.

## Windows Packaging Notes (Important)
Fixes proven in `v0.1.7`:
- Windows installer excludes non-Windows launchers (`.command`, macOS shell launcher, Linux shell launcher).
- Release build patches `bin/open890.bat` to use:
  - `cd /d "%~dp0\.."`
- Smoke workflow validates both:
  - non-Windows files are absent in Windows install root
  - installed `bin/open890.bat` contains the `cd /d` drive-switch line

Fixes proven in `v0.1.8`:
- `open890-launcher.ps1`: cmd.exe quote-stripping bug — `Start-Process` with 4-quote argument caused Windows to run `C:\Program` instead of the full path. Fixed by wrapping the command in outer quotes.
- `open890-launcher.ps1`: Desktop path resolution under elevation — `GetFolderPath("Desktop")` resolved to admin/system Desktop. Fixed by using `$env:USERPROFILE\Desktop` first.
- Smoke workflow now tests startup via PS1 launcher (`-Headless`) in addition to direct `bin\open890.bat` invocation.
- `publish-release` now blocked on `smoke-ubuntu`, `smoke-windows`, and `smoke-macos`.

If Windows startup regresses, inspect smoke traced logs first:
- `open890-start-stdout.log`
- `open890-start-stderr.log`
- `open890-readiness-probe.log`
- `launcher-stdout.log`
- `launcher-stderr.log`
- `installed-bin-open890.bat`

## Post-Release Checklist
- Confirm release is published (not draft, not missing assets).
- Spot-check installer download links.
- Run and pass Windows installer smoke workflow on released installer URL.
- Post announcement using templates in `docs/ANNOUNCEMENTS.md`.

## Post-Release Support Logging
After announcing a release, check incoming issues and log outcomes in `docs/RELEASE_INCIDENTS.md`.

1. List open issues:
   - `gh issue list --repo w9fyi/open890 --state open --limit 30`
2. Review new issues:
   - `gh issue view <issue_number> --repo w9fyi/open890`
3. Triage with required details:
   - exact installer filename/version
   - launch path used (desktop/start-menu vs direct `bin/open890.bat`)
   - diagnostics bundle or setup log attachment
4. Record incident and corrective action summary in:
   - `docs/RELEASE_INCIDENTS.md`
