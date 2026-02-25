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

### When CI fails before publish-release (safe to reuse the tag)
If `smoke-windows`, `smoke-ubuntu`, or `smoke-macos` fails, `publish-release` is blocked and
**no release assets are uploaded**. No users have downloaded anything. You can safely reuse the tag:

1. Verify no GitHub Release was created:
   - `gh release view vX.Y.Z --repo w9fyi/open890` should say "release not found"
2. Push fix commit first.
3. Delete local tag:
   - `git tag -d vX.Y.Z`
4. Delete remote tag:
   - `git push origin :refs/tags/vX.Y.Z`
5. Recreate annotated tag at current HEAD:
   - `git tag -a vX.Y.Z -m "open890 vX.Y.Z"`
6. Push tag:
   - `git push origin vX.Y.Z`

### When publish-release already ran (use a new patch version)
If assets were published and users may have downloaded them, do not reuse the tag.
Create a new patch version instead:
   - `./pushrelease vX.Y.(Z+1)`

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
- `open890-launcher.ps1`: cmd.exe quote-stripping bug — `Start-Process` using `/c "<path>" args` caused Windows to strip the outer quotes, then try to run `C:\Program` instead of the full path when installed to `C:\Program Files\open890` (the default). Fixed by wrapping the entire command in an extra outer pair of `"` and passing it as an array element: `-ArgumentList @("/d", "/c", "`"<cmd>`"")`.
- `open890-launcher.ps1`: Desktop path resolution under elevation — `GetFolderPath("Desktop")` resolved to admin/system Desktop rather than user Desktop. Fixed by using `$env:USERPROFILE\Desktop` first.
- `open890-launcher.ps1`: Erlang release log dir (`$RootDir\log\`) now collected in diagnostics bundle.
- `publish-release` now blocked on `smoke-ubuntu`, `smoke-windows`, and `smoke-macos`.
- Smoke-windows uses **direct server start** (not PS1 launcher) + a content-check assertion:
  - `Verify PS1 launcher quote fix` — asserts installed PS1 contains the outer-quote `ArgumentList` pattern
  - `Start open890 server and wait for readiness` — starts `bin\open890.bat start` directly, polls port 4000

**Why not test the PS1 launcher in CI:** `Start-Process powershell.exe -Wait` with the PS1 launcher hung indefinitely in CI (10-min job timeout), likely because the child PowerShell session blocks on console/job-object inherited from the runner. Testing the underlying server start + asserting PS1 content is equivalent coverage.

If Windows startup regresses, download `smoke-windows-diagnostics` artifact and inspect:
- `open890-install.log` — Inno Setup log (confirms what was installed and where)
- `open890-server.log` — stdout+stderr from `bin\open890.bat start` (shows cmd.exe or Erlang errors)
- Windows Application Event Log entries (if beam/erlang/vcruntime errors occurred)

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
