# Security

This project is in early development and does not yet publish supported binary
release branches. Security fixes are made on `main`.

## Reporting

Do not publish API keys, private source text, history files, signed provisioning
profiles, or exploit details in a public issue.

Use [GitHub private vulnerability reporting](https://github.com/Lakphy/apple-copilot/security/advisories/new)
when enabled for this repository. If that option is unavailable, open a general issue
requesting a private contact channel without describing the vulnerability or
including sensitive data. There is no guaranteed response-time commitment yet.

Useful reports describe the affected revision and platform, the boundary crossed,
and minimal reproduction steps with dummy credentials and public text.

## Relevant boundaries

- Endpoint-scoped Keychain credentials and refusal to forward credentials through redirects.
- HTTPS endpoint validation; HTTP is restricted to explicitly enabled loopback services.
- App Group files, cross-process locking, completed-turn persistence, and deletion tombstones.
- Sanitized Markdown, a bundled WebKit document, and the native script-message bridge.
- Explicit remote image downloads without model credentials or cookies.

See [data and privacy](Docs/PRIVACY.md) and [validation](Docs/VALIDATION.md) for the
implementation and verification scope. These documents describe current behavior;
they are not a claim of an independent security audit.
