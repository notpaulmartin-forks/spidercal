# AGENTS.md

## Installing the app after an implementation

When an implementation is complete (it builds and you've checked it works), reinstall `/Applications/Spidercal.app` from the working tree so the owner can use it straight away:

```bash
xcodebuild -quiet -project Itsycal.xcodeproj -scheme Itsycal -configuration Release -derivedDataPath <scratch folder> build
pkill -x Spidercal
rm -rf /Applications/Spidercal.app
ditto <scratch folder>/Build/Products/Release/Spidercal.app /Applications/Spidercal.app
open /Applications/Spidercal.app
```

- Build into a scratch folder, not `build/`, which `make_dmg.sh` uses.
- Check that it's running afterwards (`pgrep -x Spidercal`).
- Installing isn't a release: it doesn't need a commit, a push or a new version, and uncommitted changes are fine.

## Releasing a new DMG

Do this only when asked. A release is public.

1. Commit and push the changes the release should contain.
2. Pick the version. The tag must match the version shown in the app: `v<MARKETING_VERSION>`, currently `v0.28.0`. If that tag already exists, raise `MARKETING_VERSION` in `Itsycal.xcodeproj/project.pbxproj` first, and commit and push that too.
3. Build from a clean checkout of that commit, not the working tree:

   ```bash
   git clone <this repo> <temp folder>/spidercal
   <temp folder>/spidercal/make_dmg.sh
   ```

   This creates `build/Spidercal.dmg` in the clone: a universal app, plus a shortcut to Applications and the `Licenses` folder.
4. Mount the DMG read-only and check it before publishing:
   - `lipo -archs` on the app shows `x86_64 arm64`.
   - `codesign --verify --deep --strict` passes.
   - `codesign -d --entitlements - --xml` doesn't list `get-task-allow`.
   - `strings -a` on the app's binary finds no local paths or personal details (`/Users/`, the username, the email address). The owner's name is meant to be there: it's in the copyright in Settings › About and `Info.plist`, as in `LICENSE.txt`.
5. Publish it:

   ```bash
   gh release create v<version> <clone>/build/Spidercal.dmg \
     --repo notpaulmartin-forks/spidercal \
     --target <commit> \
     --title "Spidercal <version>" \
     --notes-file <notes>
   ```

   The notes must include the first-open steps from the README's install instructions.
6. Check that `https://github.com/notpaulmartin-forks/spidercal/releases/latest/download/Spidercal.dmg` serves the same file, by comparing `shasum -a 256` of the download and the local DMG.

### Rules

- **Keep the asset name `Spidercal.dmg`.** The README's download link depends on it.
- **The build isn't notarized.** There is no Developer ID certificate, so macOS blocks the app on first open. The README and release notes must keep saying how to get past that. Notarizing needs a Developer ID certificate, plus signing and notarization steps in `make_dmg.sh`.
- **Don't sign releases with the Apple Development certificate.** It doesn't remove the warning, and it puts the owner's email address in a public file.
- **Licences ship with the binary.** If you bundle another third-party library, add its licence to `ThirdPartyLicenses/` and copy it into the DMG in `make_dmg.sh`.
- **A release and the installed app are separate.** Publishing a release doesn't reinstall `/Applications/Spidercal.app`, and reinstalling it (see above) doesn't publish anything.
