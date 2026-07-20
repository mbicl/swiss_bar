# Installing swiss_bar

## Download

Grab the latest `.dmg` from [GitHub Releases](https://github.com/mbicl/swiss_bar/releases).
Open it and drag `swiss_bar.app` to `/Applications`.

## Why macOS warns about it

`swiss_bar` isn't distributed through the Mac App Store, and it isn't signed with an Apple
Developer ID or notarized by Apple — this project isn't enrolled in the paid Apple Developer
Program. Every release *is* code-signed, just with a self-signed certificate instead of one
Apple issued. Gatekeeper only trusts Apple-issued certificates, so the first time you try to
open the app you'll see something like:

> "swiss_bar.app" cannot be opened because the developer cannot be verified.

This is expected. Use either option below to open it anyway.

### Option A — Terminal (fastest)

```sh
xattr -cr /Applications/swiss_bar.app
```

This clears the quarantine flag macOS attaches to anything downloaded from the internet.
Run it once per install/update.

### Option B — System Settings

1. Try to open `swiss_bar.app` (double-click, or from Launchpad). macOS will block it.
2. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**
   next to the swiss_bar message.
3. Confirm in the dialog that appears.

## Permissions

On first launch, swiss_bar will ask for:

- **Accessibility** — required for the window switcher (raising/activating windows across
  apps and Spaces) and keyboard cleaning mode.
- **Input Monitoring** — used as a fallback signal alongside Accessibility.

Grant these in **System Settings → Privacy & Security → Accessibility / Input Monitoring**.

Because every release is signed with the same certificate, these grants persist across
updates — you won't be asked to re-grant them just because you installed a newer version.
If you ever see them reset, it usually means the release was built with a different signing
identity than the one you last approved; check the release notes.

## Building from source instead

If you'd rather not deal with any of the above, you can build swiss_bar yourself in Xcode
(uses your own local Apple ID for signing, no Gatekeeper warning at all for locally-built
apps):

```sh
git clone https://github.com/mbicl/swiss_bar.git
cd swiss_bar
open swiss_bar.xcodeproj
```

Then Build & Run (⌘R) from Xcode.
