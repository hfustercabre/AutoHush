# Security policy

## Reporting a vulnerability

Please report it privately, not in a public issue: open the repository's
**Security** tab and click **Report a vulnerability**
([direct link](https://github.com/hfustercabre/AutoHush/security/advisories/new)).
Say what you found, how to reproduce it, and which version of AutoHush and
macOS you used. Only you and I can see the report; I'll answer there, and
credit you in the advisory if you wish once a fix is out.

## Supported versions

Only the latest release gets fixes. AutoHush updates itself, so a fix
reaches everyone with the next version.

## What's in scope

- **AutoHush's self-update:** how it finds, downloads and checks a new
  version before replacing itself.
- **What AutoHush does with its permissions:** Accessibility, Automation
  and Audio Recording, and macOS's private interfaces it uses (with their
  fallbacks).
- **The tools in `Tools/`**, Player Check's mouse and keyboard block
  included.

Not in scope: the media players and web apps AutoHush controls, and macOS
itself. Report those to their makers.
