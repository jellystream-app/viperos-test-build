# ViperOS

ViperOS is a custom **Debian 13 (Trixie)** system with a GNOME Shell 48
desktop, its own appearance, the ViperOS Hub, and Calamares installation.
Debian remains the technical base; ViperOS is the user-facing identity
throughout the session.

Since **2.0**, everything that makes ViperOS *ViperOS* ships as Debian
packages from its own signed APT repository. That is the difference that
matters: in 1.0 the Hub, the theme and the system defaults were created by
build hooks while the ISO was assembled, so whoever installed the system kept
the version from their installation medium forever. Now `apt upgrade` brings
them a newer Hub, a newer theme, new defaults — no reinstall.

## Layout

| Directory | Contents |
|---|---|
| `packages/` | the ViperOS packages (source for the APT repository) |
| `build/lb-config/` | live-build configuration for the ISO |
| `.github/workflows/` | `packages.yml` builds and publishes; `build-iso.yml` builds the ISO |
| `live-test/` | development helpers, not part of the image (git-ignored) |

### The packages

| Package | Contents |
|---|---|
| `viperos-hub` | the system centre (Python/GTK3) and `update-system` |
| `viperos-desktop-theme` | shell theme, wallpapers, GTK3/GTK4 colours |
| `viperos-panel-extension` | the ViperOS GNOME Shell extension |
| `viperos-settings` | dconf defaults, branding, **and the APT source** |
| `viperos-desktop` | metapackage pulling the four together |

All are `Architecture: all` — there is nothing compiled, only Python, CSS, JS
and images.

## The APT repository

Published to GitHub Pages at
`https://jellystream-app.github.io/viperos-apt`, because an APT repository is
nothing but static files plus a GPG signature.

`viperos-settings` installs the source and the public signing key, so an
installed ViperOS is already subscribed. To set it up on a plain Debian 13:

```
sudo curl -fsSLo /usr/share/keyrings/viperos-archive-keyring.gpg \
  https://jellystream-app.github.io/viperos-apt/viperos-archive-keyring.gpg

sudo tee /etc/apt/sources.list.d/viperos.sources >/dev/null <<EOF
Types: deb
URIs: https://jellystream-app.github.io/viperos-apt
Suites: trixie
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/viperos-archive-keyring.gpg
EOF

sudo apt update && sudo apt install viperos-desktop
```

### Publishing an update

1. Change a file under `packages/<name>/`
2. Add a `debian/changelog` entry with a new version
3. Push to `main`

`packages.yml` builds the `.deb` in a `debian:trixie` container, signs the
repository and deploys it. Installed systems see it on their next
`apt update`. Versions are per-package and rolling: a Hub fix does not wait
for a theme release.

### One-time setup

- **Settings → Pages → Source: GitHub Actions**
- **Settings → Secrets → Actions →** `APT_SIGNING_KEY`, the private key in
  ASCII-armored form (`live-test/make-signing-key.sh` generates the pair)

Keep a backup of that private key somewhere safe. Without it the repository
can never be updated again, because installed systems would reject a
signature from a different key.

## Build

The ISO is built by **GitHub Actions**, so no local machine is needed.

| Trigger | What happens |
|---|---|
| Push to `main` touching `build/**` | Preflight + ISO build, ISO as artifact (5 days) |
| Push to `main` touching `packages/**` | Packages built, APT repository published |
| Pull request | Preflight and package build, nothing published |
| Manual (`workflow_dispatch`) | Same, plus optional GitHub Release |

To start a build by hand: **Actions → Build ViperOS ISO → Run workflow**.
Enable `release` there to publish the ISO as a permanent GitHub Release;
artifacts alone expire, because the Free plan only provides 500 MB of artifact
storage while the ISO is roughly 1.8 GB. Release assets are unlimited in
total, capped at 2 GiB per file.

The ISO workflow runs in two stages. The **preflight** finishes in about two
minutes and fails fast on the problems that would otherwise surface 40 minutes
into the build:

- CRLF line endings (a single `\r` makes apt report `Unable to locate package`
  for the *last* name on a line)
- shell syntax errors and unterminated here-docs in the hooks
- packaging mistakes: a `debian/` file left executable (debhelper would
  *execute* it), Python or shell syntax errors, a `.sources` file using
  `//` comments, a package installing into `/usr/local`, or a private key
  appearing under `usr/share/keyrings`
- package names that do not exist in Trixie, and package sets that do not
  resolve together
- unreachable build hosts, **including the ViperOS repository itself**
- a changed Jellystream checksum, which hook 0015 compares under `set -e`
- dconf defaults that do not compile, and a shell theme too small to be
  complete

Only if all of that passes does the **build** stage run `lb build` inside a
`debian:trixie` container.

### Local builds (optional)

- Windows: `scripts\BUILD.bat` (as Administrator; runs the same preflight)
- Existing Debian WSL: `bash scripts/wsl-build-direct.sh`
- Docker: build this repository and mount `/output` as the output directory
- Packages only: `packages/build-all.sh` inside a Trixie container

## Contents

GNOME Shell 48, Firefox ESR, LibreOffice, GIMP, Inkscape, Audacity, OBS
Studio, VS Code, Discord, Jellystream, KeePassXC, Remmina, FileZilla, and the
Calamares installer.

VS Code comes from Microsoft's signed APT repository, Discord from Flathub,
and Jellystream is pinned to its official GitHub release and SHA-512 checksum
for reproducible builds. Audio runs on PipeWire, which is the default stack in
Trixie. The ISO includes `shim-signed`, so it boots on machines with Secure
Boot enabled.

## Editing rules

Every file that runs inside WSL or the chroot must keep **LF** line endings;
`.gitattributes` enforces this. If a file was saved with CRLF anyway, fix it at
the source:

```
git add --renormalize .
```

`build/lb-config/auto/config` pins `--distribution trixie` deliberately. The
build target must not depend on the distribution of the build machine.

In `packages/*/debian/`, only `rules` and the maintainer scripts may be
executable. debhelper treats an executable config file as a program and runs
it, which fails the build with an unhelpful `exit code 127`. The preflight
checks the git index rather than the filesystem, because a Windows checkout
reports every file as `0755`.

## Release checks

Before distribution, boot the ISO in both UEFI and legacy BIOS virtual
machines, run the installer, and verify that the installed account is
presented instead of the temporary live account.

Then verify the point of 2.0 actually works: on the installed system, run
`apt update` and confirm the ViperOS repository is read without a signature
warning, and that `apt list --upgradable` would offer a newer ViperOS package
once one is published.
