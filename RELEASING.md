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

## Per-release: GitHub Actions + Sparkle (default path)

Pushing a version tag builds the app on GitHub Actions, attaches **ZIP + DMG**
to a GitHub Release, Sparkle-signs the ZIP, and updates [`appcast.xml`](appcast.xml)
on `main`.

**One-time CI secret** (already set if you used `gh secret set`):

```bash
# Export private key from your Mac Keychain (never commit this file)
./path/to/Sparkle/bin/generate_keys -x ed25519-private.pem
gh secret set SPARKLE_PRIVATE_KEY --repo RamiruWanigathunga/OnTime < ed25519-private.pem
rm ed25519-private.pem
```

Automatic checks are **off** (`SUEnableAutomaticChecks` = false). Users can use
**Settings → About → Check for Updates…**. Turn automatic checks on in a later
build once the first appcast item is live.

### Cut a release

1. Ensure `main` is clean and pushed.
2. Tag and push (marketing version = tag without `v`):

   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

3. Watch **Actions → Release**. When green, the Release page has
   `OnTime-vX.Y.Z.zip` + `OnTime-vX.Y.Z.dmg`, and `appcast.xml` on `main` has a
   new item. Build number = Actions `run_number` (always increasing for Sparkle).

Release builds **ad-hoc sign** the app (not Developer ID) so it can launch on
Apple Silicon. Do not strip signatures to nothing — unsigned apps are killed by
macOS. Do not `codesign --deep` (would break Sparkle’s nested XPCs). Sparkle
still verifies updates with **EdDSA** when Apple identities don’t match.

### Manual local packaging (optional)

```bash
# After a local Release build of OnTime.app:
ditto -c -k --sequesterRsrc --keepParent OnTime.app OnTime-vX.Y.Z.zip
bash scripts/make-dmg.sh OnTime.app dist/OnTime-vX.Y.Z.dmg
# Sign ZIP (uses Keychain):
sign_update OnTime-vX.Y.Z.zip
```

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
