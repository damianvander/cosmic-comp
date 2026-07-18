# cosmic-kinetic

A **patch/overlay repo** for [COSMIC](https://github.com/pop-os) that adds
compositor-side **kinetic (smooth) scrolling** with **per-app scroll-factor
overrides**, plus a settings-app UI toggle to enable it.

## Quick install

Installs both patched components — the compositor (kinetic scroll engine +
per-app scroll factors) and the settings app (UI toggles) — as prebuilt
binaries (Arch/CachyOS — see [CI](#ci)), matched to your installed COSMIC
epoch:

```bash
curl -fsSL https://raw.githubusercontent.com/damianvander/cosmic-comp/master/install-kinetic.sh | bash
```

Then log out and back in. Existing binaries are backed up to `<binary>.bak`
first. To install a single component, append `-s -- cosmic-comp` or
`-s -- cosmic-settings` to the `bash` invocation.

This repo does **not** vendor the upstream source. It carries only:

- the patch files applied on top of upstream releases,
- the end-user install script,
- CI that auto-detects new upstream `epoch-*` tags, applies the patches, and
  publishes prebuilt binaries as GitHub Releases.

The projects being patched are cloned on demand into gitignored working dirs.

## Layout

```
.
├── cosmic-comp-kinetic.patch        # cosmic-comp: kinetic engine + per-app factors
├── cosmic-settings-kinetic.patch    # cosmic-settings: smooth-scrolling UI toggle
├── install-kinetic.sh               # end-user installer (fetches prebuilt release)
├── .github/workflows/               # patch + build + release automation
├── cosmic-comp/                     # (gitignored) working clone of pop-os/cosmic-comp
└── cosmic-settings/                 # (gitignored) working clone of pop-os/cosmic-settings
```

## Working clones

The two subdirs are fresh upstream clones used to develop and regenerate the
patches. They are gitignored — recreate them any time with:

```bash
git clone https://github.com/pop-os/cosmic-comp.git     cosmic-comp
git clone https://github.com/pop-os/cosmic-settings.git cosmic-settings
```

Apply the current patches:

```bash
git -C cosmic-comp     apply ../cosmic-comp-kinetic.patch
git -C cosmic-settings apply ../cosmic-settings-kinetic.patch
```

> **Note:** `cosmic-settings-kinetic.patch` redirects the `cosmic-comp-config`
> dependency at `../cosmic-comp/cosmic-comp-config` (via a Cargo `[patch]`), so
> the new `kinetic` / `scroll_factor_per_app` config fields are visible to the
> UI. Building cosmic-settings therefore requires the **patched** cosmic-comp
> clone to exist as a sibling directory.

## Regenerating a patch after edits

```bash
git -C cosmic-comp     diff > cosmic-comp-kinetic.patch
git -C cosmic-settings diff > cosmic-settings-kinetic.patch
```

## Install (end users)

Prebuilt, patched binaries are published per upstream epoch as GitHub Releases
tagged `patched-<component>-<epoch>`.

```bash
./install-kinetic.sh                   # both components, auto-detects your epoch
./install-kinetic.sh cosmic-comp       # just the compositor
./install-kinetic.sh cosmic-settings   # just the settings app
./install-kinetic.sh epoch-1.2.0       # both, pinned to a specific epoch
```

Log out and back in (compositor) or relaunch Settings for changes to apply.
Once installed:

- Enable **Settings → Input Devices → Touchpad → Scrolling → Smooth scrolling**.
- Tune per-app scroll speed under **Settings → Input Devices → Touchpad →
  Per-app scroll speed** — add an app's Wayland app ID (or X11 WM_CLASS) and a
  multiplier (1.0 = unchanged, <1.0 slower, >1.0 faster).

## CI

`.github/workflows/patch-and-build.yml` polls upstream every 6 hours (and runs
on manual dispatch). For each component it resolves the latest `epoch-*` tag,
skips it if already released, otherwise clones upstream at that tag, applies the
patch (3-way, so minor upstream context drift self-resolves), builds, and
publishes a `patched-<component>-<epoch>` release. The cosmic-settings leg
additionally lays out a patched cosmic-comp checkout so its
`cosmic-comp-config` path patch resolves.

Builds run in an `archlinux:latest` container, so the published binaries link
against current Arch sonames and run on rolling-release systems
(Arch/CachyOS). On other distros, build from source with the patches applied.
