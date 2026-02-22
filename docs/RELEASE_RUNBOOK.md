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
   - `publish-release`
5. Verify release page assets:
   - `open890-vX.Y.Z-setup.exe`
   - `open890-vX.Y.Z-windows-x64.zip`
   - `open890-vX.Y.Z-macos-installer.pkg`
   - `open890-vX.Y.Z-macos.tar.gz`
   - `open890-vX.Y.Z-ubuntu-x64.tar.gz`
   - `open890-FIRST_TIME_SETUP.md`

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

## Post-Release Checklist
- Confirm release is published (not draft, not missing assets).
- Spot-check installer download links.
- Post announcement using templates in `docs/ANNOUNCEMENTS.md`.
