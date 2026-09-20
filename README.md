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

The repository lives in its **own** GitHub project,
`jellystream-app/viperos-apt`, separate from this one. `packages.yml` builds
and signs it here and then pushes the result to that project's `gh-pages`
branch — `actions/deploy-pages` can only serve Pages of the repository it runs
in, which is why this is a push rather than a Pages deployment. Keeping them
apart also means an ISO commit can never disturb the source every installed
system updates from.

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

In **this** repository, under Settings → Secrets and variables → Actions:

| Secret | Contents |
|---|---|
| `APT_SIGNING_KEY` | the private signing key, ASCII-armored (`live-test/make-signing-key.sh` generates the pair) |
| `APT_DEPLOY_TOKEN` | a token with write access to `jellystream-app/viperos-apt` — the run's own `GITHUB_TOKEN` is scoped to this repository only |

For the token, a fine-grained PAT is enough: Repository access → only
`viperos-apt`, Permissions → Contents: Read and write.

In **jellystream-app/viperos-apt**, after the first successful run:
Settings → Pages → Source: *Deploy from a branch*, Branch: `gh-pages` / `(root)`.

Keep a backup of the private key somewhere safe. Without it the repository can
never be updated again, because installed systems would reject a signature
from a different key. Its fingerprint is `17896F36…A118779F` and it expires in
2031.

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
Studio, VS Code, Jellystream, KeePassXC, Remmina, FileZilla, and the Calamares
installer.

VS Code comes from Microsoft's signed APT repository, and Jellystream is pinned
to its official GitHub release and SHA-512 checksum for reproducible builds.

Flathub is registered but nothing is preinstalled from it. Discord used to ship
in the image and was the single largest thing in it: Flatpak pulls the whole
Freedesktop runtime for the first application, 1-2 GB, more than LibreOffice,
firmware and fonts combined. That pushed the ISO to ~3.5 GB, over the 2 GiB
limit for GitHub release assets, and every user downloaded Discord whether they
wanted it or not. The Hub has a button to install it on demand. Audio runs on PipeWire, which is the default stack in
Trixie. The ISO includes `shim-signed`, so it boots on machines with Secure
Boot enabled.

## Installing

The live session logs in automatically as **`viperos`** (password `viperos`).
That account exists only while the system runs from the medium.

Install with the **Install ViperOS** icon on the desktop, or from the Hub. The
installer is Calamares; its configuration lives in
`build/lb-config/includes.chroot/etc/calamares/` and its appearance in
`.../usr/share/calamares/branding/viperos/`.

Two details are load-bearing and easy to break:

**The live user's name is defined in three places and they must agree.**
`auto/config` passes `username=viperos` to live-config, hook 0010 creates the
account, and `modules/removeuser.conf` names it so Calamares deletes it from
the installed system. Without the boot parameter, live-config falls back to its
own default — `user` with password `live` — and every documented credential is
wrong. Without `removeuser`, the live account survives installation with a
publicly documented password. The preflight fails the build if the three
disagree.

**The installer's tools are not pulled in automatically.** The build runs with
`--apt-recommends false`, and Calamares lists `squashfs-tools` only as a
*Recommends*. Missing, it aborts after the user has entered everything, with
`Failed to find unsquashfs`. The same applies to `dosfstools`, which provides
the `mkfs.vfat` needed for the EFI partition of any UEFI install. These
packages are therefore listed explicitly in
`package-lists/viperos-desktop.list.chroot`, and the preflight asserts they
survive dependency resolution. Do not tidy them away.

After installation, GNOME's initial setup runs once for the newly created
account and asks for language, keyboard, timezone, privacy and online accounts.
It is suppressed in the live session, where it would only offer to configure a
system that disappears at reboot.

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

The preflight proves the installer *can* work; only a real run proves it
*does*. Check all of these on the installed system:

- `id viperos` says "no such user" — the live account was removed
- `/etc/sudoers.d/viperos-live` is gone, and `/etc/motd` no longer prints
  live credentials
- on a UEFI machine, `efibootmgr` lists a **ViperOS** entry and the ESP is
  mounted at `/boot/efi`
- GNOME's initial setup appeared at the first login and does not return at
  the second
- if another OS shares the disk, it is in the GRUB menu (this is what
  `os-prober` is for; it is easy to lose to `apt autoremove`)
- `apt install --dry-run <anything>` proposes its recommended packages —
  proving the build's Recommends lock did not leak into the image

Then verify the point of 2.0 actually works: on the installed system, run
`apt update` and confirm the ViperOS repository is read without a signature
warning, and that `apt list --upgradable` would offer a newer ViperOS package
once one is published.
