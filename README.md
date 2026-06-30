# Ableton Live 12 on Linux, Wine, Wayland, and niri

One-command setup for running a licensed Ableton Live 12 install under Wine on Linux. This repo captures the setup that made Ableton Live 12.4.2 Suite usable on niri at the end of June 2026, including Serum 2.

The recommended path is patched Wine D2D/DComp, WineD3D's OpenGL renderer, and a rootful Xwayland display sized exactly to the current output, with Ableton running in a Wine virtual desktop inside it. That avoided the problems seen with the other backends:

- native Wine Wayland: right-click menus opened in place, but the pointer could not enter the popup reliably;
- rootless Xwayland/xwayland-satellite: the main UI could work, but menus appeared as centered floating windows;
- forced fullscreen niri rules: broke geometry/origin and could produce blue/black startup screens;
- DXVK: worked well for Ableton itself, but Serum 2 graphics could turn blue/black or partially redraw incorrectly;
- patched WineD3D/Vulkan: hit a `wined3d.dll` assertion during Live startup on the tested RADV system.

This repo does not provide Ableton Live, activation, serials, cracks, or downloads. You need your own licensed Ableton Live 12 installer/account.

## Known-Good Setup

Tagged known-good state: `known-good-2026-06-30`.

This is the setup that was working cleanly on June 30, 2026:

- Ableton Live 12.4.2 Suite
- Serum 2.1.4 VST3
- niri 26.04 on Wayland
- rootful Xwayland, floating and output-sized
- `2560x1440` output at scale `1`, tested at `165 Hz`
- patched Wine 11.11 from `d2d1-dcomp-11.11`
- WineD3D OpenGL renderer, not DXVK
- Wine builtin `d3d11`, `dxgi`, `d3d10core`, `d2d1`, `dcomp`, `dwrite`, `d3d9`, and `d3d8`
- `WINE_D3D_CONFIG=csmt=0x0`
- Ableton `Options.txt` does not contain `-_Feature.UseGpuRenderer` by default
- Ableton `Options.txt` does not contain `-_ForceOpenGlBackend`
- Serum 2 prefs keep DirectComposition and partial redraw enabled

The important negative result is `-_ForceOpenGlBackend`: it made one Ableton repaint issue look better, but caused Serum 2 editor redraw corruption to spread into Ableton's host UI. The launcher now removes that flag before startup.

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

To apply the safe prefix fixes without launching Live, close Ableton and run:

```bash
live-preflight
```

The default graphics stack is `d2d-opengl`. It builds a patched Wine branch under `~/.local/opt/wine-d2d1-11.11` if it is not already present. If you want the older DXVK path instead:

```bash
./install.sh --graphics dxvk --install-arch-deps --no-install-ableton
```

Fallback launchers:

```bash
live-preflight
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
- `~/.local/bin/live-preflight`
- `~/.local/bin/live-rootful-xwayland`
- `~/.local/bin/live-wayland`
- `~/.local/bin/live-xwayland`
- `~/.local/share/ableton-live12-linux/common.sh`
- `~/.local/share/ableton-live12-linux/live-preflight`
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

- Builds giang17's `d2d1-dcomp-11.11` Wine branch when using the default `d2d-opengl` graphics stack.
- Creates a `win64` Wine prefix when needed.
- Optionally runs a local licensed Ableton Live 12 installer.
- For the default stack, sets WineD3D `renderer=opengl` and forces `d3d11`, `dxgi`, `d3d10core`, `d2d1`, `dcomp`, `dwrite`, `d3d9`, and `d3d8` to Wine builtin DLLs.
- For the default stack, sets `WINE_D3D_CONFIG=csmt=0x0` to avoid stale Ableton host UI redraws/tracers.
- Detects the focused niri output refresh rate and passes it to rootful Xwayland with `-fakescreenfps`. This matters on high-refresh displays because Xwayland otherwise advertised a 60 Hz mode on the tested 165 Hz monitor.
- For the DXVK fallback stack, installs DXVK with `winetricks -q dxvk` unless `--skip-dxvk` is used.
- Disables Ableton's GPU renderer flag in `Options.txt` by default. The GPU renderer can trigger constant stale redraws under WineD3D/OpenGL on this setup; set `ABLETON_LIVE_GPU_RENDERER=1` before launch if the CPU UI path regresses on your machine.
- Sets Serum 2 prefs for the chosen stack. Default `d2d-opengl` enables Serum DirectComposition and partial redraw; DXVK disables both.
- Patches Ableton's saved `Preferences.cfg` geometry at launch so the rendered buffer matches the current output.
- Sets `msedgewebview2.exe` app-default DLL overrides for `d3d11`, `dxgi`, and `d2d1` to `builtin`.
- Adds WebView2 browser flags to disable GPU/direct-composition paths that crash under Wine+DXVK.
- Adds a niri rule for the rootful Xwayland window.

The `live` launchers run the stopped-app-safe prefix checks before startup.
`live-preflight` runs the same checks without launching Ableton and refuses to
run while Live is open.

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

Override rootful Xwayland's fake-screen refresh rate:

```bash
LIVE_REFRESH_RATE=165 live
```

Rootful Xwayland may still expose 60 Hz RandR modes even when launched with
`-fakescreenfps 165`. On the tested 165 Hz display, custom `xrandr` modelines
could be applied briefly but were not durable. If you want to test Mesa's
vblank behavior explicitly:

```bash
LIVE_VBLANK_MODE=0 live
```

That is not the default because it can worsen redraw behavior on some launches.
To force normal Mesa behavior even if your shell has `vblank_mode` set:

```bash
env -u vblank_mode live
```

The first time it patches a preferences file, it writes:

```text
Preferences.cfg.before-launch-geometry-autofix
```

## Stale Redraw Mitigations

If Ableton's own UI leaves tracers or does not repaint until the next click/key event, keep WineD3D's multithreaded command stream disabled. The launcher sets `WINE_D3D_CONFIG=csmt=0x0` by default.

The launcher now leaves Live's own GPU renderer disabled by default. To test it explicitly:

```bash
ABLETON_LIVE_GPU_RENDERER=1 live
```

Do not keep `-_ForceOpenGlBackend` in Ableton's `Options.txt`. It can reduce one class of Live repaint issue, but in testing it made Serum 2 editor redraw corruption spread into Ableton's host UI. The launcher removes that flag before startup.

For Serum 2.1.4, keep the default `d2d-opengl` Serum prefs:

```json
{
    "Disable DirectComposition": false,
    "Disable Partial Redraw": false,
    "Default Overview Type Is 3D": false
}
```

Changing Serum to full redraw (`"Disable Partial Redraw": true`) froze or badly stalled the editor in testing. Disabling Serum DirectComposition while keeping partial redraw enabled still produced host redraw corruption.

If the non-GPU Live UI path regresses on your machine:

```bash
ABLETON_LIVE_GPU_RENDERER=1 live
```

If you prefer WineD3D's default multithreaded command stream for performance testing:

```bash
WINE_D3D_CONFIG=csmt=0x1 live
```

That may improve performance, but can bring back async repaint artifacts on Ableton's host UI.

## WineASIO

The installer registers WineASIO and the launcher runs through `pw-jack` when it
is available, but Ableton can still keep using `MME/DirectX` in its own audio
preferences. In that state Live may show very large buffers such as `8192/4096`
samples and high reported latency even though WineASIO is installed.

For best scheduling behavior, set Ableton's audio driver type to `ASIO` and the
audio device to `WineASIO Driver` inside Live's audio preferences. The launcher
does not binary-patch Ableton's `Preferences.cfg` for this because that file is
not a stable text format.

## Options

```text
--prefix PATH          Wine prefix. Default: ~/myWinePrefixes/abletonLive12
--installer PATH       Run a local Ableton Live 12 installer in the prefix
--backend NAME         Default "live" backend: rootful-xwayland, wayland, or xwayland
--graphics NAME        d2d-opengl, dxvk, or system. Default: d2d-opengl
--wine-root PATH       Patched Wine install root
--wine-source PATH     Patched Wine source checkout
--wine-branch NAME     Patched Wine branch. Default: d2d1-dcomp-11.11
--wine-repo URL        Patched Wine repo
--width PX             Override launch-time geometry width
--height PX            Override launch-time geometry height
--refresh HZ           Override launch-time rootful Xwayland refresh
--no-create-prefix     Do not create the Wine prefix
--no-install-ableton   Do not run or auto-detect a local Ableton installer
--skip-patched-wine    Do not clone/build patched Wine
--skip-niri            Do not install the niri rule
--skip-wine-config     Do not write Wine registry settings
--skip-dxvk            Do not run winetricks dxvk
--install-arch-deps    Install common Arch packages
--dry-run              Print what would happen
```

## Verified Result

Verified on June 30, 2026:

- Ableton Live 12.4.2 Suite
- Serum 2.1.4 VST3
- patched Wine 11.11 from `d2d1-dcomp-11.11`
- niri 26.04
- Xwayland rootful display at `2560x1440+0+0`
- Xwayland launched with `-fakescreenfps 165` on the tested 165 Hz output
- AMD Radeon RX 7900 GRE with RADV
- WineD3D OpenGL renderer for Ableton and Serum 2
- WebView2 forced away from DXVK per app
- WineASIO/PipeWire playback available
- Serum 2 VST3 installed and visually usable with DirectComposition and partial redraw enabled

Observed checks:

- Ableton log reached `Default App: End InitApplication` and `Live App: End Init`.
- Ableton log reported clean startup with the patched WineD3D/OpenGL stack.
- Ableton log reported `Init: Screen at +0+0: 2560x1440, scale 1`.
- Ableton `Options.txt` did not contain `-_ForceOpenGlBackend`. Current redraw-stability testing leaves `-_Feature.UseGpuRenderer` disabled by default.
- niri reported the Xwayland window floating at the output size.
- Right-click context menus opened at the clicked Ableton location, not centered, and hover into the popup worked.
- Serum 2 no longer showed the blue/blank UI seen under DXVK, and did not leave black stale rectangles across Ableton once `-_ForceOpenGlBackend` was removed.
- Patched WineD3D/Vulkan was rejected after `wined3d.dll` asserted at `dlls/wined3d/cs.c:3261`, expression `flags & WINED3D_MAP_NOOVERWRITE`.

## License

MIT License.

Copyright (c) 2026 Sasha Duke.
