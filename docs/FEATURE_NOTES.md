# open890 Feature Notes

## Backlog

- Add a dedicated in-app **Macros** tab/editor so users can create and manage macros directly in the UI (add/edit/delete/reorder), with validation and persistence.
- Add macro **import/export** support for `config/config.toml` so existing macro sets can be migrated without manual re-entry.
- Add macro command **validation** in the UI (basic format checks + reserved token checks like `DEnnn`) before save.
- Add per-macro **test run** support (dry-run display + optional execute against connected radio).
- Add a UI page for common runtime settings (host/port/UDP/TX trim defaults) with safe bounds and help text.
- Add a generated **configuration reference** doc that clearly separates TOML settings from environment variable settings.
- Add a post-install macOS **self-check command** that verifies executable bits and reports/fixes common install issues.
- Add optional macOS **code signing + notarization** release path to reduce Gatekeeper friction for end users.
