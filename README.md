# Ableton Live 12 on Linux, Wine, Wayland, and niri

One-command setup for running a licensed Ableton Live 12 install under Wine on Linux. This repo captures the setup that made Ableton Live 12.4.2 Suite usable on niri at the end of June 2026.

The recommended path is a rootful Xwayland display sized exactly to the current output, with Ableton running in a Wine virtual desktop inside it. That avoided the problems seen with the other backends:

- native Wine Wayland: right-click menus opened in place, but the pointer could not enter the popup reliably;
- rootless Xwayland/xwayland-satellite: the main UI could work, but menus appeared as centered floating windows;
- forced fullscreen niri rules: broke geometry/origin and could produce blue/black startup screens.

This repo does not provide Ableton Live, activation, serials, cracks, or downloads. You need your own licensed Ableton Live 12 installer/account.

## Quick Start

Arch/niri users with a local Ableton installer:

```bash
git clone https://github.com/sashaduke/ableton-live12-linux.git
cd ableton-live12-linux
./install.sh --install-arch-deps --installer "$HOME/Downloads/Ableton Live 12 Suite Installer.exe"
```

If Ableton is already installed in the default prefix:

```bash
./install.sh --install-arch-deps --no-install-ableton
```

Then launch:

```bash
live
```

Fallback launchers:

```bash
live-rootful-xwayland
live-wayland
live-xwayland
```

## One-Command Remote Install

Review the script first if you care about what it does:

```bash
curl -fsSL https://raw.githubusercontent.com/sashaduke/ableton-live12-linux/main/install.sh -o /tmp/ableton-live12-linux-install.sh
less /tmp/ableton-live12-linux-install.sh
bash /tmp/ableton-live12-linux-install.sh --install-arch-deps --installer "$HOME/Downloads/Ableton Live 12 Suite Installer.exe"
```

For an already-installed Wine prefix:

```bash
curl -fsSL https://raw.githubusercontent.com/sashaduke/ableton-live12-linux/main/install.sh | bash -s -- --no-install-ableton
```

## What It Installs

The installer writes:

- `~/.local/bin/live`
- `~/.local/bin/live-rootful-xwayland`
- `~/.local/bin/live-wayland`
- `~/.local/bin/live-xwayland`
- `~/.local/share/ableton-live12-linux/common.sh`
- `~/.local/share/ableton-live12-linux/live-rootful-xwayland`
- `~/.local/share/ableton-live12-linux/live-wayland`
- `~/.local/share/ableton-live12-linux/live-xwayland`

By default, `live` points to `live-rootful-xwayland`.

## Default Prefix

Default Wine prefix:

```text
~/myWinePrefixes/abletonLive12
```

Override it:

```bash
./install.sh --prefix "$HOME/.wine-ableton-live12"
```

or:

```bash
ABLETON_WINEPREFIX="$HOME/.wine-ableton-live12" live
```

## What The Script Configures

- Creates a `win64` Wine prefix when needed.
- Optionally runs a local licensed Ableton Live 12 installer.
- Installs DXVK with `winetricks -q dxvk` unless `--skip-dxvk` is used.
- Enables Ableton's GPU renderer flag in `Options.txt`.
- Patches Ableton's saved `Preferences.cfg` geometry at launch so the rendered buffer matches the current output.
- Sets `msedgewebview2.exe` app-default DLL overrides for `d3d11`, `dxgi`, and `d2d1` to `builtin`, while keeping DXVK native for Ableton itself.
- Adds WebView2 browser flags to disable GPU/direct-composition paths that crash under Wine+DXVK.
- Adds a niri rule for the rootful Xwayland window.

## niri Rule

The installer inserts a managed block before `binds` in `~/.config/niri/config.kdl`:

```kdl
// BEGIN ableton-live12-linux
window-rule {
    match app-id="org.freedesktop.Xwayland" title=r#"^Xwayland on :[0-9]+$"#
    open-floating true
    draw-border-with-background false
    geometry-corner-radius 0
    clip-to-geometry false
}
// END ableton-live12-linux
```

It backs up the config before patching and runs `niri validate` when available.

## Blurry UI Fix

Ableton can persist bad window geometry such as `2572x1456` or `2560x1456` even when the actual niri output is `2560x1440`. DXVK then renders at the wrong size and the compositor scales the result, making the whole UI soft.

The launcher detects the focused niri output size and patches the saved Ableton `Preferences.cfg` geometry before startup. You can override it manually:

```bash
LIVE_WINDOW_WIDTH=1920 LIVE_WINDOW_HEIGHT=1080 live
```

The first time it patches a preferences file, it writes:

```text
Preferences.cfg.before-launch-geometry-autofix
```

## Options

```text
--prefix PATH          Wine prefix. Default: ~/myWinePrefixes/abletonLive12
--installer PATH       Run a local Ableton Live 12 installer in the prefix
--backend NAME         Default "live" backend: rootful-xwayland, wayland, or xwayland
--width PX             Override launch-time geometry width
--height PX            Override launch-time geometry height
--no-create-prefix     Do not create the Wine prefix
--no-install-ableton   Do not run or auto-detect a local Ableton installer
--skip-niri            Do not install the niri rule
--skip-wine-config     Do not write Wine registry settings
--skip-dxvk            Do not run winetricks dxvk
--install-arch-deps    Install common Arch packages
--dry-run              Print what would happen
```

## Verified Result

Verified on June 29, 2026:

- Ableton Live 12.4.2 Suite
- Wine staging 11.11
- niri 26.04
- Xwayland rootful display at `2560x1440+0+0`
- AMD Radeon RX 7900 GRE with RADV
- DXVK enabled for Ableton
- WebView2 forced away from DXVK per app
- WineASIO/PipeWire playback available

Observed checks:

- Ableton log reached `Default App: End InitApplication` and `Live App: End Init`.
- Ableton log reported `GPU Renderer: OnAlways`.
- niri reported the Xwayland window floating at `2560x1440`, position `0,0`.
- DXVK reported Ableton's main client buffer as `2552x1387`, matching the Wine virtual desktop client area without compositor scaling.
- Right-click context menus opened at the clicked Ableton location, not centered, and hover into the popup worked.
- WebView2 stayed running without creating `msedgewebview2_d3d11.log` after applying the per-app builtin overrides.

## License

MIT License.

Copyright (c) 2026 Sasha Duke.
