# Security Policy

## Supported versions

Fixes land on the latest release only. Three versions have been published:

| Version | Supported |
|---|---|
| 1.0.0 | ✅ |
| 0.2.0 | ❌ — upgrade to 1.0.0; the [CHANGELOG](CHANGELOG.md) has the migration |
| 0.1.0 | ❌ |

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting — the
[Security tab](https://github.com/aayushkedawat/bifold/security/advisories/new)
of this repository — or email **hi@aayou.sh** if you would rather not use
GitHub.

Useful things to include: the version, the platform and OS version, what an
attacker can do with it, and a reproduction if you have one.

This is a package maintained in spare time by one person, so please expect a
first reply within about a week rather than within a day. You will get an
acknowledgement, an assessment, and credit in the release notes if you want it.
If a fix is warranted it ships as a patch release with the advisory published
alongside it.

## What the attack surface actually is

Worth stating plainly, because it is small and that narrows what is worth your
time:

- **No network code.** The package makes no requests of any kind and depends
  only on `plugin_platform_interface`.
- **No permissions.** The Android manifest declares none — the hinge sensor and
  the window layout APIs need none — and there is no `Info.plist` entry on iOS.
- **Nothing is persisted.** No files, no preferences, no caches. Capability
  evidence lives in memory for the life of the process and is gone after that.
- **`Bifold.diagnosticReport()` builds a string and returns it.** Nothing is
  transmitted. It carries no identifier beyond the model string, and it is up
  to the caller whether to show it, log it or send it anywhere.

So the plausible reports are about what the package *reads* and *hands to your
app*: data arriving over the method channel from the platform, geometry that
could be made to produce a bad layout, or a second Flutter engine on the rear
display. Those are real and worth reporting.

A capability reporting the wrong value, or a crash from ordinary use, is a bug
rather than a vulnerability — please
[open an issue](https://github.com/aayushkedawat/bifold/issues/new/choose) for
those.
