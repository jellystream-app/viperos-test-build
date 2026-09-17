# ViperOS

ViperOS is a custom **Debian 13 (Trixie)** live system with an XFCE desktop, a
ViperOS Hub, Calamares installation, and privacy-focused defaults. Debian
remains the technical base; ViperOS is the user-facing identity throughout the
session.

## Build

The ISO is built by **GitHub Actions**, so no local machine is needed.

| Trigger | What happens |
|---|---|
| Push to `main` touching `build/**` | Preflight + ISO build, ISO as artifact (5 days) |
| Pull request | Preflight + ISO build (no release) |
| Manual (`workflow_dispatch`) | Same, plus optional GitHub Release |

To start a build by hand: **Actions → Build ViperOS ISO → Run workflow**. Enable
`release` there to publish the ISO as a permanent GitHub Release; artifacts
alone expire, because the Free plan only provides 500 MB of artifact storage
while the ISO is roughly 1.8 GB. Release assets are unlimited in total, capped
at 2 GiB per file.

The workflow runs in two stages. The **preflight** finishes in about two minutes
and fails fast on the problems that would otherwise surface 40 minutes into the
build:

- CRLF line endings (a single `\r` makes apt report `Unable to locate package`
  for the *last* name on a line)
- shell syntax errors and unterminated here-docs in the hooks
- package names that do not exist in Trixie, and package sets that do not
  resolve together
- unreachable build hosts (Debian mirrors, Microsoft's VS Code repo, Flathub)
- a changed Jellystream checksum, which hook 0015 compares under `set -e`

Only if all of that passes does the **build** stage run `lb build` inside a
`debian:trixie` container.

### Local builds (optional)

- Windows: `scripts\BUILD.bat` (as Administrator; runs the same preflight)
- Existing Debian WSL: `bash scripts/wsl-build-direct.sh`
- Docker: build this repository and mount `/output` as the output directory

All paths normalize the source directories into live-build's required `config/`
layout and strip CR from everything the chroot parses. The generated ISO and its
SHA-256 sidecar file are written to `output/`.

## Contents

XFCE 4.20 desktop, Firefox ESR, LibreOffice, GIMP, Inkscape, Audacity, OBS
Studio, VS Code, Discord, Jellystream, KeePassXC, Remmina, FileZilla, and the
Calamares installer.

VS Code comes from Microsoft's signed APT repository, Discord from Flathub, and
Jellystream is pinned to its official GitHub release and SHA-512 checksum for
reproducible builds. Audio runs on PipeWire, which is the default stack in
Trixie. The ISO includes `shim-signed`, so it boots on machines with Secure Boot
enabled.

## Editing rules

Every file that runs inside WSL or the chroot must keep **LF** line endings;
`.gitattributes` enforces this. If a file was saved with CRLF anyway, fix it at
the source:

```
git add --renormalize .
```

`build/lb-config/auto/config` pins `--distribution trixie` deliberately. The
build target must not depend on the distribution of the build machine.

## Release checks

Before distribution, boot the ISO in both UEFI and legacy BIOS virtual machines,
run the installer, and verify that the installed account is presented instead of
the temporary live account.
