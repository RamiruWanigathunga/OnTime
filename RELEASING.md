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

Pushing a version tag builds the app on GitHub Actions, attaches **versioned
ZIP + DMG** plus **stable aliases** (`OnTime.zip` / `OnTime.dmg`), Sparkle-signs
the versioned ZIP, and updates [`appcast.xml`](appcast.xml) on `main`.

### Always-latest download aliases

Each release uploads four assets:

| Asset | Purpose |
| --- | --- |
| `OnTime-vX.Y.Z.zip` / `.dmg` | History, Sparkle enclosure URL, pinning a version |
| `OnTime.zip` / `OnTime.dmg` | Stable names on that release |

While a release is **latest**, these URLs always resolve to its aliases:

- https://github.com/RamiruWanigathunga/OnTime/releases/latest/download/OnTime.dmg
- https://github.com/RamiruWanigathunga/OnTime/releases/latest/download/OnTime.zip

When you ship `v1.5.3`, those same URLs point at `1.5.3`. Older tags (e.g.
`v1.5.2`) keep their versioned files on the Releases page. Sparkle continues to
use the **versioned** ZIP URL in `appcast.xml`.

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
2. Bump **both** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the
   Xcode project (Sparkle uses the integer build; it must increase every time).
   Commit that bump.
3. Tag and push (marketing version = tag without `v`):

   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

4. Watch **Actions → Release**. When green: versioned + alias ZIP/DMG on the
   Release page, and a new `appcast.xml` item on `main`.

Release builds use Xcode ad-hoc signing (`CODE_SIGN_IDENTITY=-`), same as
GitStreak — that re-seals Sparkle after header stripping. CI verifies with
`codesign --verify --deep --strict`. Sparkle updates use **EdDSA**. Without
notarization, first browser install may need `xattr -cr /Applications/OnTime.app`.

**Terminal install (always latest ZIP):**

```bash
curl -fsSL -o /tmp/OnTime.zip https://github.com/RamiruWanigathunga/OnTime/releases/latest/download/OnTime.zip \
&& rm -rf /tmp/OnTime-extract \
&& ditto -x -k /tmp/OnTime.zip /tmp/OnTime-extract \
&& rm -rf /Applications/OnTime.app \
&& mv /tmp/OnTime-extract/OnTime.app /Applications/ \
&& xattr -cr /Applications/OnTime.app \
&& open /Applications/OnTime.app
```

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
- [ ] GitHub Release uploaded (versioned + `OnTime.zip` / `OnTime.dmg` aliases)
- [ ] `appcast.xml` updated on `main` (versioned ZIP URL)
- [ ] Smoke-test always-latest URLs resolve to this release
- [ ] Smoke-test: install previous build → Check for Updates → installs new ZIP
