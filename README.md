# cosmic-kinetic

A **patch/overlay repo** for [COSMIC](https://github.com/pop-os) that adds
compositor-side **kinetic (smooth) scrolling** with **per-app scroll-factor
overrides**, plus a settings UI to configure it.

This repo does **not** vendor the upstream source. It carries only:

- the patch files applied on top of upstream releases,
- the end-user install script,
- CI that auto-detects new upstream `epoch-*` tags, applies the patches, and
  publishes prebuilt binaries as GitHub Releases.

The projects being patched are cloned on demand into gitignored working dirs.

## Layout

```
.
├── kinetic-scrolling.patch          # cosmic-comp: kinetic scrolling engine
├── kinetic-overrides.patch          # cosmic-comp: per-app scroll-factor overrides
├── install-kinetic-cosmic-comp.sh   # end-user installer (fetches prebuilt release)
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

Apply the current patches into the cosmic-comp clone:

```bash
git -C cosmic-comp apply ../kinetic-scrolling.patch
git -C cosmic-comp apply ../kinetic-overrides.patch
```

## Install (end users)

```bash
./install-kinetic-cosmic-comp.sh
```

This downloads the latest patched `cosmic-comp` binary from Releases and
installs it. Log out and back in (or restart `cosmic-comp.service`) to apply.
