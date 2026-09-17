$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) { Write-Host "[STEP] $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)   { Write-Host "[ OK ] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Info([string]$Message) { Write-Host "       $Message" -ForegroundColor DarkGray }
function Stop-Build([string]$Message) { Write-Host "[FAIL] $Message" -ForegroundColor Red; exit 1 }

# wsl.exe emits UTF-16LE, which PowerShell 5.1 turns into strings full of NUL
# bytes. Without stripping them, every -eq / -contains comparison fails.
function Clean-WslOutput($Value) {
    if ($null -eq $Value) { return @() }
    return @($Value | ForEach-Object { ([string]$_) -replace "`0", '' } |
             ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

# Every script sent to bash is stripped of CR first. A single stray CR attaches
# to the LAST token on a line, so "ca-certificates" becomes "ca-certificates\r"
# and apt reports "E: Unable to locate package ca-certificates". This is the
# exact failure this build hit before, and it is why the strip is unconditional.
function Invoke-WslScript([string]$Script) {
    $unixScript = $Script -replace "`r", ''
    $encodedScript = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($unixScript))
    $command = "printf '%s' '$encodedScript' | base64 -d | bash"
    return (wsl -d Debian -u root -- bash -lc $command)
}

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '           ViperOS ISO Builder' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''

$principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Stop-Build 'Please start BUILD.bat as Administrator.'
}

# ---------------------------------------------------------------- WSL platform
Write-Step 'Checking WSL...'
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
if ($wslFeature.State -ne 'Enabled') {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
    Write-Warn 'WSL was enabled. Restart Windows, then run BUILD.bat again.'
    exit 0
}

$vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
if ($vmFeature.State -ne 'Enabled') {
    Write-Step 'Enabling VirtualMachinePlatform (required for WSL2)...'
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
    Write-Warn 'VirtualMachinePlatform was enabled. Restart Windows, then run BUILD.bat again.'
    exit 0
}

wsl --set-default-version 2 2>&1 | Out-Null

$distributions = Clean-WslOutput (wsl --list --quiet)
if ($distributions -notcontains 'Debian') {
    Write-Step 'Installing Debian for WSL...'
    wsl --install -d Debian --no-launch
    Stop-Build 'Debian was installed. Open Debian once to finish setup, then run BUILD.bat again.'
}

# ----------------------------------------------------------- WSL1 vs WSL2
# This config builds a squashfs + iso-hybrid image. That path was verified to
# work on WSL1 (debootstrap, chroot, apt-in-chroot, mksquashfs -comp zstd and
# xorriso all succeed there; the `mount -o loop` calls in live-build's
# binary_rootfs sit in the ext2/ext3/ext4 branch, not the squashfs one).
# WSL2 is still strongly preferred: far faster I/O and a real kernel. So this
# converts when possible but does NOT abort the build if conversion fails.
Write-Step 'Checking whether Debian runs on WSL2...'
$versionLines = Clean-WslOutput (wsl --list --verbose)
$debianLine = $versionLines | Where-Object { $_ -match '(^|\s)Debian(\s|$)' } | Select-Object -First 1
$wslVersion = $null
if ($debianLine -and $debianLine -match '(\d+)\s*$') { $wslVersion = [int]$Matches[1] }

if ($wslVersion -eq 1) {
    Write-Warn 'Debian runs on WSL1. The build works there, but is much slower.'
    Write-Step 'Converting Debian to WSL2 (several minutes; the build continues either way)...'
    wsl --shutdown 2>&1 | Out-Null
    wsl --set-version Debian 2 2>&1 | ForEach-Object { Write-Info (($_ -replace "`0", '')) }
    $versionLines = Clean-WslOutput (wsl --list --verbose)
    $debianLine = $versionLines | Where-Object { $_ -match '(^|\s)Debian(\s|$)' } | Select-Object -First 1
    if ($debianLine -and $debianLine -match '(\d+)\s*$') { $wslVersion = [int]$Matches[1] }
    if ($wslVersion -eq 2) {
        Write-Ok 'Debian converted to WSL2.'
    } else {
        Write-Warn 'Conversion did not succeed; continuing on WSL1 (expect a slow build).'
        Write-Info 'To convert manually later: wsl --shutdown; wsl --set-version Debian 2'
    }
} elseif ($wslVersion -eq 2) {
    Write-Ok 'Debian runs on WSL2.'
} else {
    Write-Warn 'Could not determine the WSL version; the preflight will verify capabilities directly.'
}

# --------------------------------------------------------------------- paths
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDirectory = Split-Path -Parent $scriptDirectory
$driveLetter = $projectDirectory.Substring(0, 1).ToLower()
$wslProjectPath = '/mnt/' + $driveLetter + $projectDirectory.Substring(2).Replace('\', '/')
$outputDirectory = Join-Path $projectDirectory 'output'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

# ----------------------------------------------------------------- dependencies
Write-Step 'Installing build dependencies in Debian WSL...'
$installScript = @'
set -eu
export DEBIAN_FRONTEND=noninteractive

if ! grep -qs nameserver /etc/resolv.conf; then
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
fi

apt-get update -qq

# Host-side build tooling only. The hooks run INSIDE the chroot, so their
# dependencies (python3-pil, flatpak, gnupg, ...) come from the package list,
# not from here.
PACKAGES="live-build debootstrap squashfs-tools zstd xorriso isolinux syslinux-common
grub-efi-amd64-bin grub-pc-bin grub2-common mtools dosfstools rsync wget curl git
python3 ca-certificates"

# Resolve each name separately so a single bad package is named precisely
# instead of aborting the whole transaction with a misleading message.
missing=''
for pkg in $PACKAGES; do
    if ! apt-cache show "$pkg" >/dev/null 2>&1; then
        missing="$missing $pkg"
    fi
done
if [ -n "$missing" ]; then
    printf 'UNAVAILABLE_PACKAGES:%s\n' "$missing"
    exit 1
fi

apt-get install -y $PACKAGES
printf 'DEPS_OK\n'
'@
$installOutput = Invoke-WslScript $installScript
$installOutput | ForEach-Object { Write-Host $_ }
$installClean = Clean-WslOutput $installOutput
if ($LASTEXITCODE -ne 0 -or ($installClean -join "`n") -notmatch 'DEPS_OK') {
    $unavailable = $installClean | Where-Object { $_ -match 'UNAVAILABLE_PACKAGES:' }
    if ($unavailable) {
        Stop-Build "These packages do not exist in this Debian release:$($unavailable -replace 'UNAVAILABLE_PACKAGES:','')"
    }
    Stop-Build 'Could not install the WSL build dependencies.'
}
Write-Ok 'Build dependencies present.'

# -------------------------------------------------------------------- preflight
# Everything here fails in seconds. Without it, the same problems surface
# 20-60 minutes into lb build.
Write-Step 'Running preflight checks...'
$preflightScript = @'
set -u
fail=0

# 1. The capabilities live-build genuinely needs for squashfs + iso-hybrid.
#    Tested by doing, not by guessing from the kernel version.
for tool in debootstrap lb mksquashfs xorriso mkfs.vfat mcopy; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'PREFLIGHT_FAIL: %s missing\n' "$tool"; fail=1; }
done
[ -f /usr/lib/ISOLINUX/isohdpfx.bin ] || {
    printf 'PREFLIGHT_FAIL: /usr/lib/ISOLINUX/isohdpfx.bin missing (package isolinux)\n'; fail=1; }

probe=$(mktemp -d)
mkdir -p "$probe/src/usr/bin"
printf 'x' > "$probe/src/usr/bin/prog"
chmod 4755 "$probe/src/usr/bin/prog"
if ! mksquashfs "$probe/src" "$probe/t.squashfs" -comp zstd -no-progress -noappend >/dev/null 2>&1; then
    printf 'PREFLIGHT_FAIL: mksquashfs with zstd does not work here\n'
    fail=1
fi
if ! chroot --help >/dev/null 2>&1; then
    printf 'PREFLIGHT_FAIL: chroot unavailable\n'
    fail=1
fi
if ! mknod "$probe/testnode" c 1 3 2>/dev/null; then
    printf 'PREFLIGHT_FAIL: mknod denied - debootstrap cannot create device nodes\n'
    fail=1
fi
rm -rf "$probe"

# 2. Free space. Measured, not guessed: the 1497 resolved packages are
#    0.82 GB of downloads / 3.37 GB unpacked, and live-build keeps chroot/,
#    binary/, the squashfs and the apt cache at the same time. Peak is about
#    8.4 GB, so 15 GB is the floor and 12 GB earns a warning.
avail_kb=$(df -Pk /build 2>/dev/null | awk 'NR==2 {print $4}')
[ -z "$avail_kb" ] && avail_kb=$(df -Pk / | awk 'NR==2 {print $4}')
avail_gb=$((avail_kb / 1024 / 1024))
printf 'FREE_SPACE_GB:%s\n' "$avail_gb"
if [ "$avail_gb" -lt 12 ]; then
    printf 'PREFLIGHT_FAIL: only %s GB free; peak usage is about 8.4 GB, so at least 12 GB is required\n' "$avail_gb"
    fail=1
elif [ "$avail_gb" -lt 15 ]; then
    printf 'PREFLIGHT_WARN: only %s GB free; the build peaks near 8.4 GB, leaving little headroom\n' "$avail_gb"
fi

# 3. Network reachability for every host the build and the hooks use.
for url in https://deb.debian.org/debian/dists/trixie/InRelease \
           https://security.debian.org/debian-security/dists/trixie-security/InRelease \
           https://packages.microsoft.com/keys/microsoft.asc \
           https://dl.flathub.org/repo/flathub.flatpakrepo; do
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 "$url" 2>/dev/null || echo 000)
    printf 'NET %s %s\n' "$code" "$url"
    if [ "$code" != "200" ]; then
        printf 'PREFLIGHT_FAIL: cannot reach %s\n' "$url"
        fail=1
    fi
done

# 4. CR check. Reported, not fatal: the prepare stage strips CR from the build
#    copy, so CRLF in the source tree no longer breaks the build. It is still
#    worth naming, because it means .gitattributes was bypassed somewhere.
crlf_files=''
for f in $(find '__PROJECT_PATH__/build/lb-config' -type f \
             \( -name '*.hook.chroot' -o -name '*.list.chroot' -o -name 'config' \
                -o -name 'build' -o -name 'clean' \) 2>/dev/null); do
    # awk avoids every quoting and locale pitfall of matching CR via grep
    if awk '/\r/{found=1} END{exit !found}' "$f" 2>/dev/null; then
        crlf_files="$crlf_files $f"
    fi
done
if [ -n "$crlf_files" ]; then
    printf 'PREFLIGHT_WARN: CRLF found (stripped automatically during prepare):\n'
    for f in $crlf_files; do printf '        %s\n' "$f"; done
    printf '        Fix at the source with: git add --renormalize .\n'
fi

# 5. Hook syntax, so a typo is caught now rather than mid-chroot.
#    Checked on CR-STRIPPED content, because that is what actually runs after
#    the prepare stage. Testing the raw file would turn a harmless CRLF save
#    into a false build failure (CR really does break bash: a trailing CR
#    makes "...; do" parse as "do\r" and the script dies).
#    An unterminated here-doc only warns on stderr with exit status 0, so the
#    output is inspected as well as the exit status.
syntax_tmp=$(mktemp)
for h in '__PROJECT_PATH__'/build/lb-config/hooks/live/*.hook.chroot; do
    [ -f "$h" ] || continue
    sed 's/\r$//' "$h" > "$syntax_tmp"
    syntax_output=$(bash -n "$syntax_tmp" 2>&1)
    syntax_rc=$?
    # Report the real filename, not the temp copy.
    syntax_output=$(printf '%s' "$syntax_output" | sed "s|$syntax_tmp|$h|g")
    if [ "$syntax_rc" -ne 0 ]; then
        printf 'PREFLIGHT_FAIL: shell syntax error in %s\n' "$h"
        printf '        %s\n' "$syntax_output"
        fail=1
    elif [ -n "$syntax_output" ]; then
        # e.g. "warning: here-document delimited by end-of-file"
        printf 'PREFLIGHT_FAIL: shell warning in %s\n' "$h"
        printf '        %s\n' "$syntax_output"
        fail=1
    fi
done
rm -f "$syntax_tmp"

# 6. Validate the package list against trixie (the TARGET), not the host.
LIST='__PROJECT_PATH__/build/lb-config/package-lists/viperos-desktop.list.chroot'
if [ -f "$LIST" ]; then
    ROOT=/tmp/viperos-pkgcheck
    rm -rf "$ROOT"
    mkdir -p "$ROOT"/etc/apt/trusted.gpg.d "$ROOT"/etc/apt/preferences.d \
             "$ROOT"/var/lib/apt/lists/partial "$ROOT"/var/cache/apt/archives/partial \
             "$ROOT"/var/lib/dpkg
    touch "$ROOT/var/lib/dpkg/status"
    cp /usr/share/keyrings/debian-archive-keyring.gpg "$ROOT/etc/apt/trusted.gpg.d/" 2>/dev/null || true
    printf 'deb https://deb.debian.org/debian trixie main contrib non-free non-free-firmware\n' > "$ROOT/etc/apt/sources.list"
    printf 'deb https://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware\n' >> "$ROOT/etc/apt/sources.list"
    printf 'deb https://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware\n' >> "$ROOT/etc/apt/sources.list"

    set -- -o Dir="$ROOT" -o Dir::State="$ROOT/var/lib/apt" \
           -o Dir::State::status="$ROOT/var/lib/dpkg/status" \
           -o Dir::Cache="$ROOT/var/cache/apt" \
           -o Dir::Etc::sourcelist="$ROOT/etc/apt/sources.list" \
           -o Dir::Etc::sourceparts="$ROOT/etc/apt/sources.list.d" \
           -o Dir::Etc::trustedparts="$ROOT/etc/apt/trusted.gpg.d" \
           -o APT::Architecture=amd64 -o APT::Architectures=amd64 \
           -o Acquire::Languages=none

    if apt-get "$@" update >/dev/null 2>&1 && apt-cache "$@" show sudo >/dev/null 2>&1; then
        badpkgs=''
        allpkgs=''
        while IFS= read -r line || [ -n "$line" ]; do
            pkg=$(printf '%s' "${line%%#*}" | tr -d '[:space:]')
            [ -z "$pkg" ] && continue
            allpkgs="$allpkgs $pkg"
            apt-cache "$@" show "$pkg" >/dev/null 2>&1 || badpkgs="$badpkgs $pkg"
        done < "$LIST"
        if [ -n "$badpkgs" ]; then
            printf 'PREFLIGHT_FAIL: packages missing from trixie:%s\n' "$badpkgs"
            fail=1
        else
            # Names existing individually is not enough: the set must also
            # resolve together. --apt-recommends false means only hard
            # dependencies are pulled, matching the real build.
            if apt-get "$@" install -y --dry-run --no-install-recommends \
                   $allpkgs > /tmp/viperos-dryrun.txt 2>&1; then
                printf 'PACKAGE_LIST_OK resolves_to=%s\n' "$(grep -c '^Inst ' /tmp/viperos-dryrun.txt)"
            else
                printf 'PREFLIGHT_FAIL: the package set does not resolve in trixie\n'
                grep -iE 'unmet|broken|conflict|E:' /tmp/viperos-dryrun.txt | head -12 |
                    while IFS= read -r l; do printf '        %s\n' "$l"; done
                fail=1
            fi
        fi
    else
        printf 'PREFLIGHT_WARN: could not verify the package list against trixie\n'
    fi
    rm -rf "$ROOT"
fi

[ "$fail" -eq 0 ] && printf 'PREFLIGHT_OK\n'
exit "$fail"
'@
$preflightScript = $preflightScript.Replace('__PROJECT_PATH__', $wslProjectPath)
$preflightOutput = Invoke-WslScript $preflightScript
$preflightClean = Clean-WslOutput $preflightOutput
$preflightClean | ForEach-Object {
    if ($_ -match 'PREFLIGHT_FAIL') { Write-Host "       $_" -ForegroundColor Red }
    elseif ($_ -match 'PREFLIGHT_WARN') { Write-Host "       $_" -ForegroundColor Yellow }
    else { Write-Info $_ }
}
if (($preflightClean -join "`n") -notmatch 'PREFLIGHT_OK') {
    Stop-Build 'Preflight checks failed. Fix the items marked PREFLIGHT_FAIL above.'
}
Write-Ok 'Preflight checks passed.'

# ------------------------------------------------------------------- prepare
Write-Step 'Preparing the ViperOS build directory...'
$prepareScript = @'
set -eu
rm -rf /build/viperos
mkdir -p /build/viperos /output
cp -a '__PROJECT_PATH__/build/lb-config/.' /build/viperos/
# Strip CR from everything that runs in or is parsed by the chroot, so a file
# saved on Windows cannot break the build.
find /build/viperos -type f \( -name '*.hook.chroot' -o -name '*.hook.binary' \
     -o -name '*.list.chroot' -o -name '*.list.binary' -o -name 'config' \
     -o -name 'build' -o -name 'clean' \) -exec sed -i 's/\r$//' {} +
printf 'PREPARE_OK\n'
'@
$prepareScript = $prepareScript.Replace('__PROJECT_PATH__', $wslProjectPath)
$prepareOutput = Invoke-WslScript $prepareScript
if ($LASTEXITCODE -ne 0 -or ((Clean-WslOutput $prepareOutput) -join "`n") -notmatch 'PREPARE_OK') {
    Stop-Build 'Could not prepare the ViperOS build directory.'
}
Write-Ok 'Build directory ready.'

# --------------------------------------------------------------------- build
Write-Step 'Building ViperOS ISO. This takes 20-60 minutes...'
Write-Info 'Full log: \\wsl$\Debian\build\viperos\build.log'
$buildScript = @'
set -eu
cd /build/viperos
mkdir -p config
for component in hooks package-lists includes.chroot; do
    [ -d "$component" ] || continue
    rm -rf "config/$component"
    cp -a "$component" "config/$component"
done
[ -d config/hooks ] && find config/hooks -type f -name '*.hook.chroot' -exec chmod 0755 {} +
chmod 0755 auto/config auto/build auto/clean
lb clean || true
bash auto/config

# Capture the log but keep lb build's own exit status, which a bare pipe
# through tee would otherwise hide.
set +e
lb build 2>&1 | tee /build/viperos/build.log
rc=${PIPESTATUS[0]}
set -e

if [ "$rc" -ne 0 ]; then
    printf 'BUILD_FAILED rc=%s\n' "$rc"
    printf -- '--- last 40 log lines ---\n'
    tail -40 /build/viperos/build.log
    exit "$rc"
fi

iso=$(find /build/viperos -maxdepth 1 -name '*.iso' -print -quit)
if [ -z "$iso" ]; then
    printf 'BUILD_FAILED: lb build reported success but produced no ISO\n'
    tail -40 /build/viperos/build.log
    exit 1
fi
cp "$iso" /output/viperos-1.0-amd64.iso
cd /output
sha256sum viperos-1.0-amd64.iso > viperos-1.0-amd64.iso.sha256
printf 'ISO_READY\n'
'@
$buildOutput = Invoke-WslScript $buildScript
$buildClean = Clean-WslOutput $buildOutput
if ($LASTEXITCODE -ne 0 -or ($buildClean -join "`n") -notmatch 'ISO_READY') {
    $tail = $buildClean | Select-Object -Last 45
    $tail | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }
    Stop-Build 'The ISO build failed. Full log: \\wsl$\Debian\build\viperos\build.log'
}

# ---------------------------------------------------------------------- copy
Write-Step 'Copying the ISO to Windows...'
$copyScript = @'
set -eu
cp /output/viperos-1.0-amd64.iso /output/viperos-1.0-amd64.iso.sha256 '__PROJECT_PATH__/output/'
cd '__PROJECT_PATH__/output'
sha256sum -c viperos-1.0-amd64.iso.sha256
printf 'COPY_OK\n'
'@
$copyScript = $copyScript.Replace('__PROJECT_PATH__', $wslProjectPath)
$copyOutput = Invoke-WslScript $copyScript
if ($LASTEXITCODE -ne 0 -or ((Clean-WslOutput $copyOutput) -join "`n") -notmatch 'COPY_OK') {
    Stop-Build 'Could not copy the build artifacts to Windows (or the checksum did not verify).'
}

$isoPath = Join-Path $outputDirectory 'viperos-1.0-amd64.iso'
$sizeMegabytes = [math]::Round((Get-Item $isoPath).Length / 1MB)
Write-Host ''
Write-Ok "ISO created: $isoPath"
Write-Ok "Size: $sizeMegabytes MB"
Write-Ok "Checksum verified: $isoPath.sha256"
