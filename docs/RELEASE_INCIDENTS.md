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
