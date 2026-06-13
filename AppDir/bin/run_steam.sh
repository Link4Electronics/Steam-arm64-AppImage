#!/bin/sh
# Debug: this line MUST appear if the script is executed at all.
echo "[steam-arm-launcher] STARTED at $(date)" >&2

# Be safe: use manual error handling instead of set -e so we control
# what exits and can always print diagnostics.
set -u

STEAM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/Steam-ARM-AppImage"
STEAMROOT="$STEAM_DATA_DIR/steam"

echo "[steam-arm-launcher] STEAM_DATA_DIR=$STEAM_DATA_DIR" >&2
echo "[steam-arm-launcher] STEAMROOT=$STEAMROOT" >&2
echo "[steam-arm-launcher] HOME=$HOME" >&2
echo "[steam-arm-launcher] USER=$(id -u 2>/dev/null || echo unknown)" >&2

# Fix DNS inside container (copied resolv.conf may point to unreachable stub).
# Try several methods since /etc/resolv.conf may be a RO bind mount.
fix_dns() {
    echo "[steam-arm-launcher] Current /etc/resolv.conf:"
    cat /etc/resolv.conf 2>/dev/null || echo "  (unreadable)"

    # Test if DNS actually works first
    if command -v nslookup >/dev/null 2>&1; then
        if nslookup steamcdn-a.akamaihd.net 1.1.1.1 2>/dev/null | grep 'Name:' >/dev/null 2>&1; then
            echo "[steam-arm-launcher] DNS already working via Cloudflare, skipping fix."
            return 0
        fi
    fi

    echo "[steam-arm-launcher] DNS seems broken, trying to fix..."

    NEW_DNS="nameserver 1.1.1.1
nameserver 8.8.8.8"

    # Method 1: direct write (works if file is writable)
    printf '%s\n' "$NEW_DNS" > /etc/resolv.conf 2>/dev/null && { echo "[steam-arm-launcher] DNS fixed (direct write)"; return 0; }

    # Method 2: via temp file + cp (works if file permissions block redirect but not cp)
    printf '%s\n' "$NEW_DNS" > /tmp/resolv.conf 2>/dev/null
    cp -f /tmp/resolv.conf /etc/resolv.conf 2>/dev/null && { echo "[steam-arm-launcher] DNS fixed (cp)"; return 0; }

    # Method 3: dd (overcomes some permission quirks)
    printf '%s\n' "$NEW_DNS" | dd of=/etc/resolv.conf 2>/dev/null && { echo "[steam-arm-launcher] DNS fixed (dd)"; return 0; }

    # Method 4: chattr to make writable, then try again
    chattr -i /etc/resolv.conf 2>/dev/null || true
    printf '%s\n' "$NEW_DNS" > /etc/resolv.conf 2>/dev/null && { echo "[steam-arm-launcher] DNS fixed (chattr+write)"; return 0; }

    echo "[steam-arm-launcher] WARNING: could not override /etc/resolv.conf" >&2
    echo "[steam-arm-launcher] Will try download with existing DNS config..." >&2
    return 1
}
fix_dns || true

download_steam() {
    echo "[steam-arm-launcher] Downloading Steam ARM64 beta (first run)..."
    mkdir -p "$STEAM_DATA_DIR"
    cd "$STEAM_DATA_DIR"

    if ! command -v python3 >/dev/null 2>&1; then
        echo "[steam-arm-launcher] ERROR: python3 not found inside container." >&2
        exit 1
    fi
    echo "[steam-arm-launcher] python3 found, running manifest downloader..."

    python3 /usr/bin/download_steam_manifest.py
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "[steam-arm-launcher] ERROR: Manifest downloader failed (exit $rc). Check internet." >&2
        exit 1
    fi

    if [ ! -d "$STEAMROOT" ]; then
        echo "[steam-arm-launcher] ERROR: $STEAMROOT was not created by downloader." >&2
        exit 1
    fi

    mkdir -p "$STEAMROOT/package"
    echo "publicbeta" > "$STEAMROOT/package/beta"
    touch "$STEAMROOT/.steam-enable-steamrt64-client"

    echo "[steam-arm-launcher] Steam ARM64 beta downloaded successfully!"
}

# --- First-run download ---
if [ ! -f "$STEAMROOT/steam.sh" ]; then
    echo "[steam-arm-launcher] steam.sh not found, starting download..."
    download_steam
else
    echo "[steam-arm-launcher] steam.sh found, skipping download."
fi

# --- Symlink for persistent config ---
mkdir -p "$HOME/.steam" 2>/dev/null || echo "[steam-arm-launcher] WARNING: could not create $HOME/.steam" >&2
if [ ! -L "$HOME/.steam/steam" ]; then
    ln -sfn "$STEAMROOT" "$HOME/.steam/steam" 2>/dev/null || echo "[steam-arm-launcher] WARNING: could not symlink ~/.steam/steam" >&2
fi
echo "[steam-arm-launcher] ~/.steam/steam -> $(readlink "$HOME/.steam/steam" 2>/dev/null || echo 'broken')"

# --- Find the actual ARM64 steam binary ---
# steam.sh tries to run ubuntu12_32/steam which is x86_64 (Exec format error
# on native ARM64).  Search for an ARM64 steam binary elsewhere and symlink.
ARM64_STEAM_BIN=""
for candidate in bins_linuxarm64 steam_linuxarm64 steamrtarm64 steamrt64; do
    candidate_path="$STEAMROOT/$candidate/steam"
    if [ -f "$candidate_path" ]; then
        # Check if it's actually ARM64 (not a wrapper script or x86_64 binary)
        filetype=$(file "$candidate_path" 2>/dev/null | head -1)
        if echo "$filetype" | grep -iE 'ELF.*(aarch64|ARM aarch64)' >/dev/null 2>&1; then
            ARM64_STEAM_BIN="$candidate_path"
            echo "[steam-arm-launcher] Found ARM64 steam binary: $candidate_path"
            break
        fi
    fi
done
# Also search more broadly for any ELF named steam
if [ -z "$ARM64_STEAM_BIN" ]; then
    echo "[steam-arm-launcher] Searching broadly for ARM64 steam binary..."
    for f in $(find "$STEAMROOT" -maxdepth 5 -name 'steam' -type f 2>/dev/null); do
        filetype=$(file "$f" 2>/dev/null | head -1)
        if echo "$filetype" | grep -iE 'ELF.*(aarch64|ARM aarch64)' >/dev/null 2>&1; then
            ARM64_STEAM_BIN="$f"
            echo "[steam-arm-launcher] Found ARM64 steam: $f"
            break
        fi
    done
fi
if [ -n "$ARM64_STEAM_BIN" ]; then
    # Symlink it over the x86_64 one so steam.sh finds it
    ubuntu_steam="$STEAMROOT/ubuntu12_32/steam"
    if [ -f "$ubuntu_steam" ]; then
        mv "$ubuntu_steam" "$ubuntu_steam.x86_64" 2>/dev/null || true
    fi
    ln -sfn "$ARM64_STEAM_BIN" "$ubuntu_steam" 2>/dev/null || true
    echo "[steam-arm-launcher] Symlinked $ubuntu_steam -> $ARM64_STEAM_BIN"
fi

# --- Disable the x86_64 Steam Runtime ---
# The Steam Runtime bundled with the ARM64 beta is the x86_64 runtime
# (ubuntu12_32/steam-runtime/).  All its binaries are x86_64 Exec format
# error on native ARM64.  Disable it and rely on the system glibc/libraries.
echo "[steam-arm-launcher] Disabling Steam Runtime (x86_64-only, not usable on ARM64)..."
rm -f "$STEAMROOT/.steam-enable-steamrt64-client" 2>/dev/null || true
export STEAM_RUNTIME=0

# --- Find ARM64 runtime directory and add to library path ---
# The ARM64 beta may have multiple runtime dirs (steamrtarm64,
# runtime_steamrt_linuxarm64, etc.).  Add only the ARM64 one to
# LD_LIBRARY_PATH — steamrt64 might be x86_64 and would make the
# linker load the wrong libvpx.so.6 etc.
ARM64_RUNTIME_DIR=""
for rt in steamrtarm64 runtime_steamrt_linuxarm64 bins_steamrt_linuxarm64 steamrt64; do
    candidate="$STEAMROOT/$rt"
    if [ -d "$candidate" ]; then
        # Check a .so in the dir to see if it's ARM64
        sample=$(find "$candidate" -maxdepth 2 -name '*.so*' -type f 2>/dev/null | head -1)
        if [ -n "$sample" ]; then
            if file "$sample" 2>/dev/null | grep -iE 'ELF.*(aarch64|ARM aarch64)' >/dev/null 2>&1; then
                ARM64_RUNTIME_DIR="$candidate"
                echo "[steam-arm-launcher] Found ARM64 runtime: $candidate"
                break
            fi
        fi
    fi
done
if [ -n "$ARM64_RUNTIME_DIR" ]; then
    # Add the runtime dir AND any library subdirectories (lib/, usr/lib/, etc.)
    RUNTIME_LD_DIRS="$ARM64_RUNTIME_DIR"
    for subdir in $(find "$ARM64_RUNTIME_DIR" -type d -name 'lib' -o -type d -path '*/lib/*' 2>/dev/null); do
        RUNTIME_LD_DIRS="$RUNTIME_LD_DIRS:$subdir"
    done
    export LD_LIBRARY_PATH="${RUNTIME_LD_DIRS}:${LD_LIBRARY_PATH:-}"
    echo "[steam-arm-launcher] added to LD_LIBRARY_PATH: ${RUNTIME_LD_DIRS}"
else
    echo "[steam-arm-launcher] WARNING: no ARM64 runtime directory found" >&2
fi

# --- Make helpers executable (only ARM64 ones) ---
for f in steam steamwebhelper steamwebhelper.sh gldriverquery \
         vulkandriverquery steamsysinfo; do
    find "$STEAMROOT" -maxdepth 5 -name "$f" -type f 2>/dev/null | while IFS= read -r found; do
        filetype=$(file "$found" 2>/dev/null | head -1)
        if echo "$filetype" | grep -iE 'ELF.*(aarch64|ARM aarch64)|POSIX shell script' >/dev/null 2>&1; then
            chmod +x "$found" 2>/dev/null || true
            echo "[steam-arm-launcher] made executable: $found ($(echo "$filetype" | cut -d, -f1))"
        fi
    done
done

# --- Symlink bin/ for Steam's hardcoded paths (bin/vgui2_s.dll etc.) ---
# Steam hardcodes paths like bin/vgui2_s.dll but the ARM64 beta uses
# depot names like bins_linuxarm64 or bins_steamrt_linuxarm64.
# Symlink all Steam module files into a flat bin/ directory.
mkdir -p "$STEAMROOT/bin" 2>/dev/null || echo "[steam-arm-launcher] WARNING: could not create $STEAMROOT/bin" >&2
find "$STEAMROOT" -maxdepth 5 -type f \( -name '*_s.so' -o -name '*_s.dll' -o -name 'steamclient.so' -o -name 'steamui.so' -o -name 'gameoverlayrenderer.so' -o -name 'gameoverlayui.so' \) \
  ! -path "$STEAMROOT/bin/*" 2>/dev/null | while read -r f; do
    name=$(basename "$f")
    if [ ! -e "$STEAMROOT/bin/$name" ]; then
        ln -sfn "$f" "$STEAMROOT/bin/$name" 2>/dev/null || true
    fi
    # Steam on Linux looks for modules with .dll extension (vgui2_s.dll etc.)
    case "$name" in
        *.so)
            dll_name="${name%.so}.dll"
            if [ ! -e "$STEAMROOT/bin/$dll_name" ]; then
                ln -sfn "$f" "$STEAMROOT/bin/$dll_name" 2>/dev/null || true
            fi
            ;;
    esac
done
echo "[steam-arm-launcher] bin/ contents: $(ls "$STEAMROOT/bin/" 2>/dev/null | tr '\n' ' ' || echo '(empty)')"

# --- Patch steam.sh for ARM64 ---
# Replace ubuntu12_32/steam with steamrtarm64/steam in exec commands.
# This survives Steam restarts: when Steam updates and re-runs steam.sh,
# it goes straight to the ARM64 binary instead of the x86_64 one.
sed -i 's|ubuntu12_32/steam|steamrtarm64/steam|g' "$STEAMROOT/steam.sh" 2>/dev/null || true

# --- Allow running as root (CI containers etc.) ---
sed -i 's|"$(id -u)" == "0"|"$(id -u)" == "69"|' "$STEAMROOT/steam.sh" 2>/dev/null || echo "[steam-arm-launcher] root-patch skipped (steam.sh missing or already patched)" >&2

# --- Rebuild library cache ---
echo "[steam-arm-launcher] Running ldconfig..."
ldconfig 2>/dev/null || echo "[steam-arm-launcher] WARNING: ldconfig failed" >&2

if [ ! -f "$STEAMROOT/steam.sh" ]; then
    echo "[steam-arm-launcher] FATAL: steam.sh not found. Cannot launch Steam." >&2
    echo "[steam-arm-launcher] Contents of $STEAMROOT:" >&2
    ls -la "$STEAMROOT/" 2>/dev/null || echo "  (STEAMROOT does not exist)" >&2
    exit 1
fi

# Set VERSION_ID for Arch Linux which omits it from /etc/os-release
export VERSION_ID="${VERSION_ID:-0}"

chmod +x "$STEAMROOT/steam.sh" 2>/dev/null || echo "[steam-arm-launcher] WARNING: could not chmod steam.sh" >&2
echo "[steam-arm-launcher] Launching Steam from $STEAMROOT ..."
cd "$STEAMROOT"
exec ./steam.sh -noverifyfiles "$@"
