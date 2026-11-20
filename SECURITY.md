# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| Latest GitHub Release | Yes |
| Older releases | Best effort; please upgrade |

## Reporting a Vulnerability

OnTime is a local macOS menu-bar app. We take security seriously — especially
anything that could affect update integrity (Sparkle), local data, or privilege
escalation.

### How to Report

1. **GitHub Private Vulnerability Reporting (preferred)**  
   On the public repository, open
   [Security Advisories](https://github.com/RamiruWanigathunga/OnTime/security/advisories)
   and choose **Report a vulnerability**.

2. **Alternative**  
   If private reporting is unavailable, open a GitHub Issue with **minimal**
   details and ask for a private channel, or contact the maintainer listed on
   the repository profile.

> [!IMPORTANT]
> **Do not** report security vulnerabilities through public issues or
> discussions with full exploit details.

## What to Expect

* **Acknowledgment** within **48 hours** when possible.
* **Status updates** every **3–5 business days** while investigating.
* **If accepted**: a fix in an upcoming release (GitHub Releases + Sparkle
  appcast when updates are enabled). Credit in release notes if you want it.
* **If declined**: a clear explanation of why it is not treated as a security
  issue.

## Update Integrity

Release ZIPs are signed with Sparkle EdDSA. Never share or commit the Sparkle
**private** key. See [RELEASING.md](RELEASING.md).
