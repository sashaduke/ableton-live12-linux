#!/usr/bin/env bash
set -euo pipefail

repo_name="ableton-live12-linux"
default_prefix="$HOME/myWinePrefixes/abletonLive12"
prefix="${ABLETON_WINEPREFIX:-$default_prefix}"
bin_dir="${BIN_DIR:-$HOME/.local/bin}"
support_dir="${XDG_DATA_HOME:-$HOME/.local/share}/ableton-live12-linux"
niri_config="${NIRI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl}"
default_backend="rootful-xwayland"
graphics_stack="${ABLETON_GRAPHICS_STACK:-d2d-opengl}"
patched_wine_repo="${ABLETON_PATCHED_WINE_REPO:-https://github.com/giang17/wine.git}"
patched_wine_branch="${ABLETON_PATCHED_WINE_BRANCH:-d2d1-dcomp-11.11}"
patched_wine_source="${ABLETON_PATCHED_WINE_SOURCE:-$HOME/src/wine-d2d1}"
patched_wine_root="${ABLETON_PATCHED_WINE_ROOT:-$HOME/.local/opt/wine-d2d1-11.11}"
build_patched_wine=1
install_arch_deps=0
create_prefix=1
configure_dxvk=1
configure_niri=1
configure_wine=1
run_installer=1
installer_path="${ABLETON_INSTALLER:-}"
dry_run=0

usage() {
  cat <<'EOF'
Install Ableton Live 12 Wine/niri launchers.

Usage:
  ./install.sh [options]

Options:
  --prefix PATH          Wine prefix. Default: ~/myWinePrefixes/abletonLive12
  --installer PATH       Run a local Ableton Live 12 installer in the prefix
  --backend NAME         Default "live" backend: rootful-xwayland, wayland, or xwayland
  --graphics NAME        d2d-opengl, dxvk, or system. Default: d2d-opengl
  --wine-root PATH       Patched Wine install root. Default: ~/.local/opt/wine-d2d1-11.11
  --wine-source PATH     Patched Wine source checkout. Default: ~/src/wine-d2d1
  --wine-branch NAME     Patched Wine branch. Default: d2d1-dcomp-11.11
  --wine-repo URL        Patched Wine repo. Default: https://github.com/giang17/wine.git
  --width PX             Override launch-time geometry width, saved into launcher env
  --height PX            Override launch-time geometry height, saved into launcher env
  --refresh HZ           Override launch-time rootful Xwayland refresh, saved into launcher env
  --no-create-prefix     Do not create the Wine prefix when it is missing
  --no-install-ableton   Do not run or auto-detect a local Ableton installer
  --skip-patched-wine    Do not clone/build the patched Wine tree
  --skip-niri            Do not install the niri main-window rule
  --skip-wine-config     Do not write Wine registry settings
  --skip-dxvk            Do not run "winetricks -q dxvk"
  --install-arch-deps    Install common Arch packages with pacman/paru
  --dry-run              Print what would happen without writing files
  -h, --help             Show this help

After install:
  live                    Rootful Xwayland launcher, recommended for niri
  live-preflight          Apply safe stopped-app prefix fixes without launching Live
  live-rootful-xwayland   Same as the default when --backend rootful-xwayland is used
  live-wayland            Native Wine Wayland fallback
  live-xwayland           Rootless/Xwayland-satellite fallback

This script does not download, crack, activate, or distribute Ableton Live.
It can run a local licensed Ableton Live 12 installer if you provide one.
EOF
}

log() {
  printf '[%s] %s\n' "$repo_name" "$*"
}

warn() {
  printf '[%s] warning: %s\n' "$repo_name" "$*" >&2
}

die() {
  printf '[%s] error: %s\n' "$repo_name" "$*" >&2
  exit 1
}

run() {
  if [[ "$dry_run" -eq 1 ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || die "--prefix needs a path"
      prefix="$2"
      shift 2
      ;;
    --installer)
      [[ $# -ge 2 ]] || die "--installer needs a path"
      installer_path="$2"
      run_installer=1
      shift 2
      ;;
    --backend)
      [[ $# -ge 2 ]] || die "--backend needs rootful-xwayland, wayland, or xwayland"
      default_backend="$2"
      shift 2
      ;;
    --graphics)
      [[ $# -ge 2 ]] || die "--graphics needs d2d-opengl, dxvk, or system"
      graphics_stack="$2"
      shift 2
      ;;
    --wine-root)
      [[ $# -ge 2 ]] || die "--wine-root needs a path"
      patched_wine_root="$2"
      shift 2
      ;;
    --wine-source)
      [[ $# -ge 2 ]] || die "--wine-source needs a path"
      patched_wine_source="$2"
      shift 2
      ;;
    --wine-branch)
      [[ $# -ge 2 ]] || die "--wine-branch needs a branch name"
      patched_wine_branch="$2"
      shift 2
      ;;
    --wine-repo)
      [[ $# -ge 2 ]] || die "--wine-repo needs a URL"
      patched_wine_repo="$2"
      shift 2
      ;;
    --width)
      [[ $# -ge 2 ]] || die "--width needs a number"
      export LIVE_WINDOW_WIDTH="$2"
      shift 2
      ;;
    --height)
      [[ $# -ge 2 ]] || die "--height needs a number"
      export LIVE_WINDOW_HEIGHT="$2"
      shift 2
      ;;
    --refresh)
      [[ $# -ge 2 ]] || die "--refresh needs a number"
      export LIVE_REFRESH_RATE="$2"
      shift 2
      ;;
    --no-create-prefix)
      create_prefix=0
      shift
      ;;
    --no-install-ableton)
      run_installer=0
      shift
      ;;
    --skip-patched-wine)
      build_patched_wine=0
      shift
      ;;
    --skip-niri)
      configure_niri=0
      shift
      ;;
    --skip-wine-config)
      configure_wine=0
      shift
      ;;
    --skip-dxvk)
      configure_dxvk=0
      shift
      ;;
    --install-arch-deps)
      install_arch_deps=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

case "$default_backend" in
  rootful-xwayland|wayland|xwayland) ;;
  *) die "--backend must be rootful-xwayland, wayland, or xwayland" ;;
esac

case "$graphics_stack" in
  d2d-opengl|dxvk|system) ;;
  *) die "--graphics must be d2d-opengl, dxvk, or system" ;;
esac

if [[ -n "${LIVE_WINDOW_WIDTH:-}" && ! "${LIVE_WINDOW_WIDTH:-}" =~ ^[0-9]+$ ]]; then
  die "--width must be numeric"
fi

if [[ -n "${LIVE_WINDOW_HEIGHT:-}" && ! "${LIVE_WINDOW_HEIGHT:-}" =~ ^[0-9]+$ ]]; then
  die "--height must be numeric"
fi

if [[ -n "${LIVE_REFRESH_RATE:-}" && ! "${LIVE_REFRESH_RATE:-}" =~ ^[0-9]+$ ]]; then
  die "--refresh must be numeric"
fi

uses_patched_wine() {
  [[ "$graphics_stack" == "d2d-opengl" && -n "$patched_wine_root" ]]
}

wine_path() {
  if uses_patched_wine; then
    printf '%s:%s\n' "$patched_wine_root/bin" "$PATH"
  else
    printf '%s\n' "$PATH"
  fi
}

wine_binary() {
  if uses_patched_wine && [[ -x "$patched_wine_root/bin/wine" ]]; then
    printf '%s\n' "$patched_wine_root/bin/wine"
    return 0
  fi

  command -v wine 2>/dev/null || return 1
}

winepath_binary() {
  if uses_patched_wine && [[ -x "$patched_wine_root/bin/winepath" ]]; then
    printf '%s\n' "$patched_wine_root/bin/winepath"
    return 0
  fi

  command -v winepath 2>/dev/null || return 1
}

wineboot_binary() {
  if uses_patched_wine && [[ -x "$patched_wine_root/bin/wineboot" ]]; then
    printf '%s\n' "$patched_wine_root/bin/wineboot"
    return 0
  fi

  command -v wineboot 2>/dev/null || return 1
}

wineserver_binary() {
  if uses_patched_wine && [[ -x "$patched_wine_root/bin/wineserver" ]]; then
    printf '%s\n' "$patched_wine_root/bin/wineserver"
    return 0
  fi

  command -v wineserver 2>/dev/null || return 1
}

ableton_running() {
  pgrep -f '[A]bleton Live 12 .*\.exe' >/dev/null 2>&1
}

find_installed_ableton_exe() {
  local candidates=()
  shopt -s nullglob
  candidates=(
    "$prefix"/drive_c/ProgramData/Ableton/Live\ 12*/Program/Ableton\ Live\ 12*.exe
    "$prefix"/drive_c/Program\ Files/Ableton/Live\ 12*/Program/Ableton\ Live\ 12*.exe
  )
  shopt -u nullglob

  if [[ "${#candidates[@]}" -gt 0 ]]; then
    printf '%s\n' "${candidates[0]}"
  fi
}

find_local_ableton_installer() {
  if [[ -n "$installer_path" ]]; then
    printf '%s\n' "$installer_path"
    return 0
  fi

  local candidates=()
  shopt -s nullglob nocaseglob
  candidates=(
    "$PWD"/*Ableton*Live*12*.exe
    "$PWD"/*ableton*live*12*.exe
    "$HOME"/Downloads/*Ableton*Live*12*.exe
    "$HOME"/Downloads/*ableton*live*12*.exe
  )
  shopt -u nullglob nocaseglob

  if [[ "${#candidates[@]}" -eq 1 ]]; then
    printf '%s\n' "${candidates[0]}"
  elif [[ "${#candidates[@]}" -gt 1 ]]; then
    warn "multiple Ableton installers found; pass one explicitly with --installer PATH"
    printf '%s\n' "${candidates[@]}" >&2
  fi
}

install_common_arch_deps() {
  [[ "$install_arch_deps" -eq 1 ]] || return 0

  if ! command -v pacman >/dev/null 2>&1; then
    warn "--install-arch-deps was requested, but pacman is not installed"
    return 0
  fi

  local packages=(
    base-devel
    fontconfig
    freetype2
    git
    glibc
    gnutls
    gst-plugins-base-libs
    libglvnd
    libpulse
    libx11
    libxext
    libxi
    libxrandr
    libxrender
    mesa
    vulkan-headers
    vulkan-icd-loader
    vulkan-radeon
    wine-staging
    winetricks
    wineasio
    xorg-xwayland
    xwayland-satellite
    pipewire-jack
    python
    perl
  )

  log "Installing common Arch dependencies"
  if command -v paru >/dev/null 2>&1; then
    run paru -S --needed "${packages[@]}"
  elif command -v yay >/dev/null 2>&1; then
    run yay -S --needed "${packages[@]}"
  else
    run sudo pacman -S --needed "${packages[@]}"
  fi
}

install_patched_wine_if_requested() {
  [[ "$graphics_stack" == "d2d-opengl" ]] || return 0
  [[ "$build_patched_wine" -eq 1 ]] || {
    warn "patched Wine build was skipped; expecting a compatible Wine at $patched_wine_root"
    return 0
  }

  if [[ -x "$patched_wine_root/bin/wine" ]]; then
    log "Patched Wine already exists at $patched_wine_root"
    return 0
  fi

  local required=(git make)
  local cmd
  for cmd in "${required[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd is required to build patched Wine"
  done
  command -v gcc >/dev/null 2>&1 || command -v cc >/dev/null 2>&1 || die "a C compiler is required to build patched Wine"

  log "Building patched Wine for Serum 2 D2D/DComp"
  log "Repo: $patched_wine_repo"
  log "Branch: $patched_wine_branch"
  log "Source: $patched_wine_source"
  log "Install root: $patched_wine_root"

  if [[ "$dry_run" -eq 1 ]]; then
    log "Would clone/update $patched_wine_repo branch $patched_wine_branch"
    log "Would run: ./configure --prefix=$patched_wine_root --enable-win64"
    log "Would run: make -j$(nproc 2>/dev/null || printf 4)"
    log "Would run: make install"
    return 0
  fi

  mkdir -p "$(dirname "$patched_wine_source")" "$(dirname "$patched_wine_root")"
  if [[ -d "$patched_wine_source/.git" ]]; then
    git -C "$patched_wine_source" fetch origin "$patched_wine_branch"
    git -C "$patched_wine_source" checkout "$patched_wine_branch"
    git -C "$patched_wine_source" pull --ff-only origin "$patched_wine_branch"
  else
    git clone --depth 1 --branch "$patched_wine_branch" "$patched_wine_repo" "$patched_wine_source"
  fi

  local jobs
  jobs="$(nproc 2>/dev/null || printf 4)"
  (
    cd "$patched_wine_source"
    ./configure --prefix="$patched_wine_root" --enable-win64
    make -j"$jobs"
    make install
  )
}

create_wine_prefix_if_needed() {
  [[ "$create_prefix" -eq 1 ]] || return 0

  if [[ -d "$prefix/drive_c" ]]; then
    return 0
  fi

  local wine_bin wineboot_bin wineserver_bin
  wine_bin="$(wine_binary || true)"
  wineboot_bin="$(wineboot_binary || true)"
  wineserver_bin="$(wineserver_binary || true)"
  [[ -n "$wine_bin" && -n "$wineboot_bin" ]] || {
    warn "Wine is not installed, so the prefix cannot be created yet"
    warn "Install Wine, then rerun this script"
    return 0
  }

  if ableton_running; then
    warn "Ableton is running; not creating/updating the Wine prefix"
    return 0
  fi

  log "Creating Wine prefix at $prefix"
  run mkdir -p "$prefix"
  if [[ "$dry_run" -eq 1 ]]; then
    log "Would run: WINEPREFIX=$prefix WINEARCH=win64 $wineboot_bin -u"
  else
    env WINEPREFIX="$prefix" WINEARCH=win64 PATH="$(wine_path)" "$wineboot_bin" -u
    if [[ -n "$wineserver_bin" ]]; then
      env WINEPREFIX="$prefix" WINEARCH=win64 PATH="$(wine_path)" "$wineserver_bin" -w || true
    fi
  fi
}

register_wineasio_if_available() {
  command -v wineasio-register >/dev/null 2>&1 || return 0
  [[ -d "$prefix/drive_c" ]] || return 0
  ableton_running && return 0

  if wineasio_registered; then
    log "WineASIO already registered in the prefix"
    return 0
  fi

  log "Registering wineasio in the prefix"
  if [[ "$dry_run" -eq 1 ]]; then
    log "Would run: WINEPREFIX=$prefix wineasio-register"
  else
    env WINEPREFIX="$prefix" WINEARCH=win64 PATH="$(wine_path)" wineasio-register || warn "wineasio-register failed; continuing"
    if ! wineasio_registered; then
      register_wineasio64_with_unified_wine || warn "wineasio64 fallback registration failed; continuing"
    fi
  fi
}

wineasio_registered() {
  local wine_bin
  wine_bin="$(wine_binary || true)"
  [[ -n "$wine_bin" ]] || return 1

  env WINEPREFIX="$prefix" WINEARCH=win64 WINEDEBUG=-all PATH="$(wine_path)" \
    "$wine_bin" reg query 'HKLM\Software\ASIO\WineASIO' >/dev/null 2>&1
}

register_wineasio64_with_unified_wine() {
  local wine_bin unix_dll windows_dll
  wine_bin="$(wine_binary || true)"
  [[ -n "$wine_bin" ]] || return 1
  [[ -d "$prefix/drive_c/windows/syswow64" ]] || return 1

  local candidates=(
    /opt/wine-devel/lib64/wine/x86_64-unix/wineasio64.dll.so
    /opt/wine-stable/lib64/wine/x86_64-unix/wineasio64.dll.so
    /opt/wine-staging/lib64/wine/x86_64-unix/wineasio64.dll.so
    /usr/lib/wine/x86_64-unix/wineasio64.dll.so
    /usr/lib64/wine/x86_64-unix/wineasio64.dll.so
    /usr/lib/x86_64-linux-gnu/wine/x86_64-unix/wineasio64.dll.so
  )

  for unix_dll in "${candidates[@]}"; do
    windows_dll="${unix_dll/x86_64-unix\/wineasio64.dll.so/x86_64-windows\/wineasio64.dll}"
    [[ -f "$unix_dll" && -f "$windows_dll" ]] || continue

    log "Registering wineasio64 with unified Wine regsvr32 fallback"
    cp -f "$windows_dll" "$prefix/drive_c/windows/system32/"
    env WINEPREFIX="$prefix" WINEARCH=win64 WINEDEBUG=-all PATH="$(wine_path)" \
      "$wine_bin" regsvr32 "$unix_dll" >/dev/null
    return 0
  done

  return 1
}

run_ableton_installer_if_needed() {
  [[ "$run_installer" -eq 1 ]] || return 0

  if [[ -n "$(find_installed_ableton_exe)" ]]; then
    log "Ableton Live already appears to be installed in the prefix"
    return 0
  fi

  local wine_bin wineserver_bin
  wine_bin="$(wine_binary || true)"
  wineserver_bin="$(wineserver_binary || true)"
  [[ -n "$wine_bin" ]] || {
    warn "Wine is not installed, so the Ableton installer cannot run"
    return 0
  }
  [[ -d "$prefix/drive_c" ]] || {
    warn "Wine prefix does not exist yet, so the Ableton installer cannot run"
    return 0
  }
  if ableton_running; then
    warn "Ableton is running; skipping installer"
    return 0
  fi

  local installer
  installer="$(find_local_ableton_installer || true)"
  if [[ -z "$installer" ]]; then
    warn "No local Ableton Live 12 installer found"
    warn "Download your licensed Ableton installer, then rerun with: --installer /path/to/installer.exe"
    return 0
  fi
  [[ -f "$installer" ]] || die "installer not found: $installer"

  log "Running Ableton installer in the Wine prefix"
  log "Installer: $installer"
  if [[ "$dry_run" -eq 1 ]]; then
    log "Would run: WINEPREFIX=$prefix $wine_bin $installer"
  else
    env WINEPREFIX="$prefix" WINEARCH=win64 PATH="$(wine_path)" "$wine_bin" "$installer"
    if [[ -n "$wineserver_bin" ]]; then
      env WINEPREFIX="$prefix" WINEARCH=win64 PATH="$(wine_path)" "$wineserver_bin" -w || true
    fi
  fi
}

write_file_from_template() {
  local path="$1"
  local marker="$2"
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp"

  if [[ "$dry_run" -eq 1 ]]; then
    log "Would write $path"
    rm -f "$tmp"
    return 0
  fi

  python3 - "$tmp" "$support_dir" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
support_dir = sys.argv[2]
path.write_text(path.read_text().replace("__SUPPORT_DIR__", support_dir))
PY

  mkdir -p "$(dirname "$path")"
  if [[ -f "$path" ]]; then
    cp -a "$path" "$path.before-$marker-$(date +%Y%m%d-%H%M%S)"
  fi
  mv "$tmp" "$path"
  chmod +x "$path"
}

write_launchers() {
  log "Installing launchers into $bin_dir"
  run mkdir -p "$bin_dir" "$support_dir"

  local common="$support_dir/common.sh"

  if [[ "$dry_run" -eq 1 ]]; then
    log "Would write $common"
  else
    cat >"$common" <<'COMMON'
#!/usr/bin/env bash
set -euo pipefail

: "${ABLETON_WINEPREFIX:=__ABLETON_WINEPREFIX__}"
: "${ABLETON_WINE_ROOT:=__ABLETON_WINE_ROOT__}"
: "${ABLETON_GRAPHICS_STACK:=__ABLETON_GRAPHICS_STACK__}"
: "${ABLETON_LIVE_GPU_RENDERER:=1}"
: "${LIVE_WINDOW_WIDTH:=__LIVE_WINDOW_WIDTH__}"
: "${LIVE_WINDOW_HEIGHT:=__LIVE_WINDOW_HEIGHT__}"
: "${LIVE_REFRESH_RATE:=__LIVE_REFRESH_RATE__}"
: "${WINEARCH:=win64}"
: "${WINEDEBUG:=-all}"

if [[ -n "$ABLETON_WINE_ROOT" ]]; then
  export PATH="$ABLETON_WINE_ROOT/bin:$PATH"
fi

export WINEPREFIX="$ABLETON_WINEPREFIX"
export WINEARCH
export WINEDEBUG

if [[ "$ABLETON_GRAPHICS_STACK" == "d2d-opengl" ]]; then
  export WINE_D3D_CONFIG="${WINE_D3D_CONFIG:-csmt=0x0}"
  if [[ -n "${LIVE_VBLANK_MODE:-}" ]]; then
    export vblank_mode="$LIVE_VBLANK_MODE"
  fi
fi

wine_cmd="${WINE_BIN:-wine}"
winepath_cmd="${WINEPATH_BIN:-winepath}"

dxvk_log_dir="${DXVK_LOG_PATH:-$HOME/.cache/ableton-live12/dxvk}"
mkdir -p "$dxvk_log_dir"
export DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-info}"
export DXVK_LOG_PATH="$dxvk_log_dir"

webview2_flags="--disable-gpu --disable-gpu-compositing --disable-direct-composition --disable-accelerated-2d-canvas"
if [[ -n "${WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS:-}" ]]; then
  export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="$WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS $webview2_flags"
else
  export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="$webview2_flags"
fi

export PIPEWIRE_LATENCY="${PIPEWIRE_LATENCY:-256/48000}"
export WINEASIO_NUMBER_INPUTS="${WINEASIO_NUMBER_INPUTS:-2}"
export WINEASIO_NUMBER_OUTPUTS="${WINEASIO_NUMBER_OUTPUTS:-2}"
export WINEASIO_FIXED_BUFFERSIZE="${WINEASIO_FIXED_BUFFERSIZE:-on}"
export WINEASIO_PREFERRED_BUFFERSIZE="${WINEASIO_PREFERRED_BUFFERSIZE:-256}"
export WINEASIO_CONNECT_TO_HARDWARE="${WINEASIO_CONNECT_TO_HARDWARE:-on}"

ableton_running() {
  pgrep -f '[A]bleton Live 12 .*\.exe' >/dev/null 2>&1
}

detect_target_geometry() {
  if [[ -n "${LIVE_WINDOW_WIDTH:-}" && -n "${LIVE_WINDOW_HEIGHT:-}" ]]; then
    printf '%s %s\n' "$LIVE_WINDOW_WIDTH" "$LIVE_WINDOW_HEIGHT"
    return 0
  fi

  if command -v niri >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    local geometry
    geometry="$(
      niri msg -j focused-output 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    logical = data.get("logical") or {}
    width = int(logical.get("width") or 0)
    height = int(logical.get("height") or 0)
    if width > 0 and height > 0:
        print(f"{width} {height}")
except Exception:
    pass
' 2>/dev/null || true
    )"
    if [[ -n "$geometry" ]]; then
      printf '%s\n' "$geometry"
      return 0
    fi
  fi

  printf '2560 1440\n'
}

detect_target_refresh() {
  if [[ -n "${LIVE_REFRESH_RATE:-}" ]]; then
    printf '%s\n' "$LIVE_REFRESH_RATE"
    return 0
  fi

  if command -v niri >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    local refresh
    refresh="$(
      niri msg -j focused-output 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    modes = data.get("modes") or []
    current = int(data.get("current_mode"))
    rate = int(modes[current].get("refresh_rate") or 0)
    if rate > 0:
        print(max(1, min(600, round(rate / 1000))))
except Exception:
    pass
' 2>/dev/null || true
    )"
    if [[ -n "$refresh" ]]; then
      printf '%s\n' "$refresh"
      return 0
    fi
  fi

  printf '60\n'
}

patch_ableton_geometry() {
  command -v perl >/dev/null 2>&1 || return 0
  ableton_running && return 0

  local target_w target_h
  read -r target_w target_h < <(detect_target_geometry)
  [[ "$target_w" =~ ^[0-9]+$ && "$target_h" =~ ^[0-9]+$ ]] || return 0

  local prefs_base="$WINEPREFIX/drive_c/users/$USER/AppData/Roaming/Ableton"
  local prefs_files=()
  shopt -s nullglob
  prefs_files=("$prefs_base"/Live\ 12*/Preferences/Preferences.cfg)
  shopt -u nullglob

  local prefs
  for prefs in "${prefs_files[@]}"; do
    [[ -f "$prefs" ]] || continue
    local backup="$prefs.before-launch-geometry-autofix"
    [[ -e "$backup" ]] || cp -a "$prefs" "$backup"

    LIVE_TARGET_WIDTH="$target_w" LIVE_TARGET_HEIGHT="$target_h" perl -0777 -i -pe '
      my $target_w = pack("V", int($ENV{LIVE_TARGET_WIDTH} || 2560));
      my $target_h = pack("V", int($ENV{LIVE_TARGET_HEIGHT} || 1440));
      my $patched = 0;

      s{
        (\x10RemoteableString\x03\x00\x00\x00.{8})
        (.{4})(.{4})
        (\x00\x00\x01\x02)
      }{
        my ($prefix, $w, $h, $suffix) = ($1, $2, $3, $4);
        my $old_w = unpack("V", $w);
        my $old_h = unpack("V", $h);

        if (!$patched && $old_w >= 1000 && $old_w <= 10000 && $old_h >= 700 && $old_h <= 10000) {
          $patched = 1;
          $prefix . $target_w . $target_h . $suffix;
        } else {
          $&;
        }
      }gsex;
    ' "$prefs"
  done
}

configure_live_graphics_options() {
  ableton_running && return 0

  local prefs_base="$WINEPREFIX/drive_c/users/$USER/AppData/Roaming/Ableton"
  local pref_dirs=()
  shopt -s nullglob
  pref_dirs=("$prefs_base"/Live\ 12*/Preferences)
  shopt -u nullglob

  local pref_dir options
  for pref_dir in "${pref_dirs[@]}"; do
    [[ -d "$pref_dir" ]] || continue
    options="$pref_dir/Options.txt"
    touch "$options"

    local tmp
    tmp="$(mktemp)"
    grep -vxF -- '-_ForceOpenGlBackend' "$options" >"$tmp" || true
    mv "$tmp" "$options"

    if [[ "$ABLETON_LIVE_GPU_RENDERER" == "0" || "$ABLETON_LIVE_GPU_RENDERER" == "false" ]]; then
      tmp="$(mktemp)"
      grep -vxF -- '-_Feature.UseGpuRenderer' "$options" >"$tmp" || true
      mv "$tmp" "$options"
    else
      grep -qxF -- '-_Feature.UseGpuRenderer' "$options" || printf '%s\n' '-_Feature.UseGpuRenderer' >>"$options"
    fi
  done
}

configure_serum2_prefs() {
  ableton_running && return 0
  command -v python3 >/dev/null 2>&1 || return 0

  local prefs="$WINEPREFIX/drive_c/users/$USER/AppData/Roaming/Xfer/Serum 2/Serum2Prefs.json"
  [[ -f "$prefs" ]] || return 0

  python3 - "$prefs" "$ABLETON_GRAPHICS_STACK" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
graphics = sys.argv[2]
try:
    data = json.loads(path.read_text())
except Exception:
    data = {}

if graphics == "d2d-opengl":
    data["Disable DirectComposition"] = False
    data["Disable Partial Redraw"] = False
else:
    data["Disable DirectComposition"] = True
    data["Disable Partial Redraw"] = True

data["Default Overview Type Is 3D"] = False
data.setdefault("Default Zoom", 100)
path.write_text(json.dumps(data, indent=4, sort_keys=True) + "\n")
PY
}

ensure_webview2_builtin_overrides() {
  command -v wine >/dev/null 2>&1 || return 0
  ableton_running && return 0

  local key='HKCU\Software\Wine\AppDefaults\msedgewebview2.exe\DllOverrides'
  local dll
  for dll in d3d11 dxgi d2d1; do
    WINEDEBUG=-all "$wine_cmd" reg add "$key" /v "$dll" /t REG_SZ /d builtin /f >/dev/null 2>&1 || true
  done
}

find_ableton_exe() {
  if [[ -n "${ABLETON_EXE:-}" ]]; then
    printf '%s\n' "$ABLETON_EXE"
    return 0
  fi

  local candidates=()
  shopt -s nullglob
  candidates=(
    "$WINEPREFIX"/drive_c/ProgramData/Ableton/Live\ 12*/Program/Ableton\ Live\ 12*.exe
    "$WINEPREFIX"/drive_c/Program\ Files/Ableton/Live\ 12*/Program/Ableton\ Live\ 12*.exe
  )
  shopt -u nullglob

  if [[ "${#candidates[@]}" -gt 0 ]]; then
    printf '%s\n' "${candidates[0]}"
    return 0
  fi

  printf '%s\n' "$WINEPREFIX/drive_c/ProgramData/Ableton/Live 12 Suite/Program/Ableton Live 12 Suite.exe"
}

find_ableton_exe_windows() {
  local exe
  exe="$(find_ableton_exe)"
  [[ -f "$exe" ]] || {
    printf '%s\n' 'C:\ProgramData\Ableton\Live 12 Suite\Program\Ableton Live 12 Suite.exe'
    return 0
  }

  if command -v "$winepath_cmd" >/dev/null 2>&1; then
    "$winepath_cmd" -w "$exe" 2>/dev/null && return 0
  fi

  printf '%s\n' 'C:\ProgramData\Ableton\Live 12 Suite\Program\Ableton Live 12 Suite.exe'
}

preflight_ableton() {
  ensure_webview2_builtin_overrides
  patch_ableton_geometry
  configure_live_graphics_options
  configure_serum2_prefs
}

run_ableton() {
  preflight_ableton

  local exe
  exe="$(find_ableton_exe)"
  if [[ ! -f "$exe" ]]; then
    cat >&2 <<EOF
Ableton Live executable was not found:
  $exe

Set ABLETON_EXE to the .exe path, or install Ableton Live 12 into:
  $WINEPREFIX
EOF
    exit 1
  fi

  if command -v pw-jack >/dev/null 2>&1; then
    exec pw-jack "$wine_cmd" "$exe" "$@"
  fi

  exec "$wine_cmd" "$exe" "$@"
}
COMMON

    local launcher_wine_root="$patched_wine_root"
    if [[ "$graphics_stack" != "d2d-opengl" ]]; then
      launcher_wine_root=""
    fi

    python3 - "$common" "$prefix" "$launcher_wine_root" "$graphics_stack" "${LIVE_WINDOW_WIDTH:-}" "${LIVE_WINDOW_HEIGHT:-}" "${LIVE_REFRESH_RATE:-}" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
prefix = sys.argv[2]
wine_root = sys.argv[3]
graphics = sys.argv[4]
width = sys.argv[5]
height = sys.argv[6]
refresh = sys.argv[7]
text = path.read_text()
text = text.replace("__ABLETON_WINEPREFIX__", prefix)
text = text.replace("__ABLETON_WINE_ROOT__", wine_root)
text = text.replace("__ABLETON_GRAPHICS_STACK__", graphics)
text = text.replace("__LIVE_WINDOW_WIDTH__", width)
text = text.replace("__LIVE_WINDOW_HEIGHT__", height)
text = text.replace("__LIVE_REFRESH_RATE__", refresh)
path.write_text(text)
PY
    chmod +x "$common"
  fi

  write_file_from_template "$support_dir/live-rootful-xwayland" "ableton-live12-linux" <<'ROOTFUL_XWAYLAND'
#!/usr/bin/env bash
set -euo pipefail

source "${ABLETON_LIVE12_SUPPORT_DIR:-__SUPPORT_DIR__}/common.sh"

if [[ "$ABLETON_GRAPHICS_STACK" == "d2d-opengl" ]]; then
  default_overrides="winemenubuilder.exe=d;winewayland.drv=d;d3d11,dxgi,d3d10core,d2d1,dcomp,dwrite,d3d9,d3d8=b"
else
  default_overrides="winemenubuilder.exe=d;winewayland.drv=d"
fi
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-$default_overrides}"

find_free_display() {
  local n
  for n in $(seq 20 99); do
    [[ -e "/tmp/.X11-unix/X$n" ]] && continue
    printf ':%s\n' "$n"
    return 0
  done
  return 1
}

wait_for_display() {
  local display="$1"
  local socket="/tmp/.X11-unix/X${display#:}"
  local i
  for i in $(seq 1 80); do
    [[ -S "$socket" ]] && return 0
    sleep 0.05
  done
  return 1
}

preflight_ableton

if ! command -v Xwayland >/dev/null 2>&1; then
  echo "Xwayland is not installed." >&2
  exit 1
fi

exe="$(find_ableton_exe)"
if [[ ! -f "$exe" ]]; then
  cat >&2 <<EOF
Ableton Live executable was not found:
  $exe

Set ABLETON_EXE to the .exe path, or install Ableton Live 12 into:
  $WINEPREFIX
EOF
  exit 1
fi
exe_windows="$(find_ableton_exe_windows)"

display="$(find_free_display)"
read -r width height < <(detect_target_geometry)
refresh="$(detect_target_refresh)"
log_dir="$HOME/.cache/ableton-live12/rootful-xwayland"
mkdir -p "$log_dir"
xwayland_log="$log_dir/xwayland-${display#:}.log"

Xwayland "$display" -ac -terminate -geometry "${width}x${height}" -fakescreenfps "$refresh" -br -decorate >"$xwayland_log" 2>&1 &
xwayland_pid=$!
trap 'kill "$xwayland_pid" 2>/dev/null || true' EXIT

if ! wait_for_display "$display"; then
  echo "Timed out waiting for rootful Xwayland display $display. Log: $xwayland_log" >&2
  exit 1
fi

export DISPLAY="$display"
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export SDL_VIDEODRIVER=x11
export CLUTTER_BACKEND=x11

if command -v pw-jack >/dev/null 2>&1; then
  exec pw-jack "$wine_cmd" explorer "/desktop=AbletonLive12,${width}x${height}" "$exe_windows" "$@"
fi

exec "$wine_cmd" explorer "/desktop=AbletonLive12,${width}x${height}" "$exe_windows" "$@"
ROOTFUL_XWAYLAND

  write_file_from_template "$support_dir/live-wayland" "ableton-live12-linux" <<'WAYLAND'
#!/usr/bin/env bash
set -euo pipefail

source "${ABLETON_LIVE12_SUPPORT_DIR:-__SUPPORT_DIR__}/common.sh"

export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  for socket in "$runtime_dir"/wayland-*; do
    [[ -S "$socket" ]] || continue
    export WAYLAND_DISPLAY="${socket##*/}"
    break
  done
fi

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "No Wayland socket found under $runtime_dir" >&2
  exit 1
fi

unset DISPLAY
unset GDK_BACKEND
unset QT_QPA_PLATFORM
unset SDL_VIDEODRIVER
unset CLUTTER_BACKEND

run_ableton "$@"
WAYLAND

  write_file_from_template "$support_dir/live-xwayland" "ableton-live12-linux" <<'XWAYLAND'
#!/usr/bin/env bash
set -euo pipefail

source "${ABLETON_LIVE12_SUPPORT_DIR:-__SUPPORT_DIR__}/common.sh"

export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d;winewayland.drv=d}"

unset WAYLAND_DISPLAY
export DISPLAY="${DISPLAY:-:1}"
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export SDL_VIDEODRIVER=x11
export CLUTTER_BACKEND=x11

run_ableton "$@"
XWAYLAND

  write_file_from_template "$support_dir/live-preflight" "ableton-live12-linux" <<'PREFLIGHT'
#!/usr/bin/env bash
set -euo pipefail

source "${ABLETON_LIVE12_SUPPORT_DIR:-__SUPPORT_DIR__}/common.sh"

if ableton_running; then
  echo "Ableton is running; close it before running live-preflight." >&2
  exit 1
fi

preflight_ableton

cat <<EOF
Ableton Live 12 preflight complete.

Prefix:
  $WINEPREFIX

Checked:
  - Ableton Options.txt graphics flags
  - saved Ableton window geometry
  - Serum 2 graphics preferences
  - WebView2 Wine DLL overrides

Note:
  If Live still shows MME/DirectX in Audio preferences, set Driver Type to ASIO
  and Audio Device to WineASIO Driver inside Live.
EOF
PREFLIGHT

  if [[ "$dry_run" -eq 0 ]]; then
    ln -sfn "$support_dir/live-preflight" "$bin_dir/live-preflight"
    ln -sfn "$support_dir/live-rootful-xwayland" "$bin_dir/live-rootful-xwayland"
    ln -sfn "$support_dir/live-wayland" "$bin_dir/live-wayland"
    ln -sfn "$support_dir/live-xwayland" "$bin_dir/live-xwayland"
    case "$default_backend" in
      rootful-xwayland) ln -sfn "$support_dir/live-rootful-xwayland" "$bin_dir/live" ;;
      wayland) ln -sfn "$support_dir/live-wayland" "$bin_dir/live" ;;
      xwayland) ln -sfn "$support_dir/live-xwayland" "$bin_dir/live" ;;
    esac
  else
    log "Would link live, live-preflight, live-rootful-xwayland, live-wayland, and live-xwayland in $bin_dir"
  fi
}

install_niri_rule() {
  [[ "$configure_niri" -eq 1 ]] || return 0
  [[ -f "$niri_config" ]] || {
    warn "niri config not found at $niri_config; skipping niri rule"
    return 0
  }

  log "Installing niri rootful-Xwayland rule"

  if [[ "$dry_run" -eq 1 ]]; then
    log "Would patch $niri_config"
    return 0
  fi

  local backup="$niri_config.before-ableton-live12-linux-$(date +%Y%m%d-%H%M%S)"
  cp -a "$niri_config" "$backup"

  python3 - "$niri_config" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
begin = "// BEGIN ableton-live12-linux"
end = "// END ableton-live12-linux"
block = """// BEGIN ableton-live12-linux
window-rule {
    match app-id="org.freedesktop.Xwayland" title=r#"^Xwayland on :[0-9]+$"#
    open-floating true
    draw-border-with-background false
    geometry-corner-radius 0
    clip-to-geometry false
}
// END ableton-live12-linux
"""

pattern = re.compile(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", re.S)
if pattern.search(text):
    text = pattern.sub(block, text)
else:
    match = re.search(r"(?m)^binds\s*\{", text)
    if match:
        text = text[:match.start()] + block + text[match.start():]
    else:
        text = text.rstrip() + "\n" + block

path.write_text(text)
PY

  if command -v niri >/dev/null 2>&1; then
    if ! niri validate >/dev/null; then
      cp -a "$backup" "$niri_config"
      die "niri config validation failed; restored $backup"
    fi
    niri msg action load-config-file >/dev/null 2>&1 || true
  fi
}

configure_wine_registry() {
  [[ "$configure_wine" -eq 1 ]] || return 0
  local wine_bin
  wine_bin="$(wine_binary || true)"
  [[ -n "$wine_bin" ]] || {
    warn "wine not found; skipping Wine registry configuration"
    return 0
  }
  [[ -d "$prefix" ]] || {
    warn "Wine prefix does not exist yet: $prefix"
    warn "Launchers were installed; rerun install.sh after creating the prefix to apply registry settings"
    return 0
  }
  if ableton_running; then
    warn "Ableton is running; skipping Wine registry writes for this install"
    return 0
  fi

  log "Configuring Wine registry for $graphics_stack/rootful Xwayland"

  local reg=(env WINEPREFIX="$prefix" WINEARCH=win64 PATH="$(wine_path)" "$wine_bin" reg add)
  local reg_delete=(env WINEPREFIX="$prefix" WINEARCH=win64 PATH="$(wine_path)" "$wine_bin" reg delete)
  if [[ "$graphics_stack" == "d2d-opengl" ]]; then
    run "${reg[@]}" 'HKCU\Software\Wine\Direct3D' /v renderer /t REG_SZ /d opengl /f >/dev/null
    run "${reg[@]}" 'HKCU\Software\Wine\DllOverrides' /v '*d3d8' /t REG_SZ /d builtin /f >/dev/null
    run "${reg[@]}" 'HKCU\Software\Wine\DllOverrides' /v '*d3d9' /t REG_SZ /d builtin /f >/dev/null
    run "${reg[@]}" 'HKCU\Software\Wine\DllOverrides' /v '*d3d10core' /t REG_SZ /d builtin /f >/dev/null
    run "${reg[@]}" 'HKCU\Software\Wine\DllOverrides' /v '*d3d11' /t REG_SZ /d builtin /f >/dev/null
    run "${reg[@]}" 'HKCU\Software\Wine\DllOverrides' /v '*dxgi' /t REG_SZ /d builtin /f >/dev/null
    run "${reg[@]}" 'HKCU\Software\Wine\DllOverrides' /v '*d2d1' /t REG_SZ /d builtin /f >/dev/null
    run "${reg[@]}" 'HKCU\Software\Wine\DllOverrides' /v '*dcomp' /t REG_SZ /d builtin /f >/dev/null
    run "${reg[@]}" 'HKCU\Software\Wine\DllOverrides' /v '*dwrite' /t REG_SZ /d builtin /f >/dev/null
  elif [[ "$graphics_stack" == "dxvk" ]]; then
    run "${reg[@]}" 'HKCU\Software\Wine\DllOverrides' /v '*d3d8' /t REG_SZ /d native /f >/dev/null
    run "${reg[@]}" 'HKCU\Software\Wine\DllOverrides' /v '*d3d9' /t REG_SZ /d native /f >/dev/null
    run "${reg[@]}" 'HKCU\Software\Wine\DllOverrides' /v '*d3d10core' /t REG_SZ /d native /f >/dev/null
    run "${reg[@]}" 'HKCU\Software\Wine\DllOverrides' /v '*d3d11' /t REG_SZ /d native /f >/dev/null
    run "${reg[@]}" 'HKCU\Software\Wine\DllOverrides' /v '*dxgi' /t REG_SZ /d native /f >/dev/null
    if [[ "$dry_run" -eq 1 ]]; then
      log "Would delete HKCU\\Software\\Wine\\Direct3D renderer"
    else
      "${reg_delete[@]}" 'HKCU\Software\Wine\Direct3D' /v renderer /f >/dev/null 2>&1 || true
    fi
  fi

  run "${reg[@]}" 'HKCU\Software\Wine\X11 Driver' /v Decorated /t REG_SZ /d N /f >/dev/null
  run "${reg[@]}" 'HKCU\Software\Wine\X11 Driver' /v Managed /t REG_SZ /d Y /f >/dev/null
  run "${reg[@]}" 'HKCU\Software\Wine\X11 Driver' /v UseTakeFocus /t REG_SZ /d N /f >/dev/null
  run "${reg[@]}" 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d 96 /f >/dev/null

  local webview_key='HKCU\Software\Wine\AppDefaults\msedgewebview2.exe\DllOverrides'
  run "${reg[@]}" "$webview_key" /v d3d11 /t REG_SZ /d builtin /f >/dev/null
  run "${reg[@]}" "$webview_key" /v dxgi /t REG_SZ /d builtin /f >/dev/null
  run "${reg[@]}" "$webview_key" /v d2d1 /t REG_SZ /d builtin /f >/dev/null

  local exe_path='C:\ProgramData\Ableton\Live 12 Suite\Program\Ableton Live 12 Suite.exe'
  run "${reg[@]}" 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' /v "$exe_path" /t REG_SZ /d '~ HIGHDPIAWARE' /f >/dev/null
}

install_dxvk_if_requested() {
  [[ "$configure_dxvk" -eq 1 ]] || return 0
  [[ "$graphics_stack" == "dxvk" ]] || return 0
  command -v winetricks >/dev/null 2>&1 || {
    warn "DXVK setup requested, but winetricks is not installed"
    return 0
  }
  [[ -d "$prefix" ]] || {
    warn "DXVK setup requested, but prefix does not exist: $prefix"
    return 0
  }
  if ableton_running; then
    warn "Ableton is running; skipping winetricks dxvk"
    return 0
  fi

  log "Installing DXVK into prefix with winetricks"
  if [[ "$dry_run" -eq 1 ]]; then
    log "Would run: WINEPREFIX=$prefix winetricks -q dxvk"
  else
    env WINEPREFIX="$prefix" WINEARCH=win64 PATH="$(wine_path)" winetricks -q dxvk || warn "winetricks dxvk failed; launchers were still installed"
  fi
}

print_summary() {
  cat <<EOF

Installed Ableton Live 12 Linux launchers.

Commands:
  live                    Default launcher ($default_backend)
  live-preflight          Apply safe stopped-app prefix fixes without launching Live
  live-rootful-xwayland   Rootful Xwayland launcher, recommended under niri
  live-wayland            Native Wine Wayland fallback
  live-xwayland           Rootless/Xwayland-satellite fallback

Prefix:
  $prefix

Graphics stack:
  $graphics_stack

Patched Wine root:
  $patched_wine_root

If the command is not found, add this to your shell PATH:
  $bin_dir

For fixed geometry on non-2560x1440 screens, launch like:
  LIVE_WINDOW_WIDTH=1920 LIVE_WINDOW_HEIGHT=1080 live

For fixed refresh on high-refresh screens, launch like:
  LIVE_REFRESH_RATE=165 live

EOF
}

install_common_arch_deps
install_patched_wine_if_requested
create_wine_prefix_if_needed
configure_wine_registry
install_dxvk_if_requested
register_wineasio_if_available
run_ableton_installer_if_needed
write_launchers
install_niri_rule
print_summary
