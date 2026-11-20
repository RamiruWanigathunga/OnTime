# Releasing OnTime

Primary distribution for the public source-available repo is **GitHub Releases**
plus **Sparkle** (EdDSA-signed ZIPs). A paid Apple Developer ID / notarization
path is optional and documented at the end for later.

## Version rules

- **Marketing version** (`CFBundleShortVersionString` / Xcode *Version*) — what
  users see (e.g. `1.0.0`). Change for every public release.
- **Build** (`CFBundleVersion` / Xcode *Build*) — integer Sparkle uses to decide
  what is newer. **Must increase** for every Sparkle-published build.

## One-time: Sparkle EdDSA keys

Never commit the private key. The public key is embedded in the app.

1. Download a Sparkle release from
   [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle/releases)
   (or use tools from a local Sparkle checkout).
2. Run:

   ```bash
   ./bin/generate_keys
   ```

3. The private key is stored in your login Keychain. Copy the printed
   **public** key into `OnTime/Info.plist` as `SUPublicEDKey` (already wired;
   replace the placeholder if regenerating).
4. Back up the private key securely offline. Losing it means you cannot sign
   updates that existing installs will trust.

Optional export for CI (keep the file out of git):

```bash
./bin/generate_keys -x path/to/ed25519-private.pem
```

Add local key paths to `.gitignore` if you keep exports on disk.

## Per-release: GitHub + Sparkle (default path)

Automatic checks are **off** (`SUEnableAutomaticChecks` = false) until you
publish the first signed item in `appcast.xml`. Users can still use
**Settings → About → Check for Updates…**.

1. Bump **Version** and **Build** in Xcode (OnTime target → General).
2. Archive or build a Release `OnTime.app` (Personal Team or ad-hoc is fine for
   this path; users may need Gatekeeper **Open Anyway** — document that in the
   release notes).
3. Zip the app (preserve symlinks):

   ```bash
   ditto -c -k --sequesterRsrc --keepParent OnTime.app OnTime-vX.Y.Z.zip
   ```

4. Sign the ZIP with Sparkle:

   ```bash
   ./bin/sign_update OnTime-vX.Y.Z.zip
   ```

   Copy the printed `sparkle:edSignature` and file length.
5. Create a GitHub Release `vX.Y.Z`, upload `OnTime-vX.Y.Z.zip`.
6. Append an `<item>` to [`appcast.xml`](appcast.xml) (see template below). Commit
   and push `appcast.xml` on `main` so
   `https://raw.githubusercontent.com/RamiruWanigathunga/OnTime/main/appcast.xml`
   updates.
7. After the first successful item, you may set `SUEnableAutomaticChecks` to
   `true` in `Info.plist` for subsequent builds if you want background checks.

### Appcast item template

```xml
<item>
  <title>Version X.Y.Z</title>
  <link>https://github.com/RamiruWanigathunga/OnTime/releases/tag/vX.Y.Z</link>
  <sparkle:version>BUILD_NUMBER</sparkle:version>
  <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
  <description><![CDATA[
    <h2>OnTime X.Y.Z</h2>
    <ul>
      <li>Highlight one</li>
    </ul>
  ]]></description>
  <pubDate>Wed, 20 Nov 2026 12:00:00 +0000</pubDate>
  <enclosure
    url="https://github.com/RamiruWanigathunga/OnTime/releases/download/vX.Y.Z/OnTime-vX.Y.Z.zip"
    sparkle:version="BUILD_NUMBER"
    sparkle:shortVersionString="X.Y.Z"
    sparkle:edSignature="PASTE_FROM_sign_update"
    length="BYTE_LENGTH"
    type="application/octet-stream" />
</item>
```

Feed URL in the app: `SUFeedURL` →
`https://raw.githubusercontent.com/RamiruWanigathunga/OnTime/main/appcast.xml`.

## Optional later: Developer ID + notarized DMG

Requires a **paid** Apple Developer Program membership.

1. Sign with **Developer ID Application**, Archive → Direct Distribution
   (notarize).
2. Verify: `spctl -a -vv /path/to/OnTime.app`
3. Package a DMG with [`scripts/make-dmg.sh`](scripts/make-dmg.sh) and
   `SIGNING_IDENTITY=…`.
4. Notarize and staple the DMG with `notarytool` / `stapler`.
5. You may still publish a ZIP for Sparkle; prefer notarized artifacts so
   Gatekeeper stays quiet.

## Mac App Store (optional, separate numbering)

App Store builds use Apple’s update channel (not Sparkle). Keep App Store
version/build numbering independent from GitHub releases if you ship both.

## Checklist

- [ ] Version + build bumped
- [ ] ZIP created with `ditto`
- [ ] `sign_update` signature + length recorded
- [ ] GitHub Release uploaded
- [ ] `appcast.xml` updated on `main`
- [ ] Smoke-test: install previous build → Check for Updates → installs new ZIP
