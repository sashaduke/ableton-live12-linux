# Reproduction Notes

These notes capture the path that worked for Ableton Live 12.4.2 Suite on niri on June 30, 2026.

## Machine

- Ableton Live 12.4.2 Suite
- Serum 2.1.4 VST3
- patched Wine 11.11, branch `d2d1-dcomp-11.11`
- niri 26.04
- AMD Radeon RX 7900 GRE, RADV
- `2560x1440` output at scale `1.0`, tested at `165 Hz`
- Wine prefix: `~/myWinePrefixes/abletonLive12`
- Ableton executable: `C:\ProgramData\Ableton\Live 12 Suite\Program\Ableton Live 12 Suite.exe`
- Serum 2 VST3 installed under the prefix's common VST3 directory

## Failed Or Partial Backends

Native Wine Wayland:

- Ableton's main UI could launch.
- Menus opened at the correct location.
- Pointer movement into popup menus failed, making menus unusable.

Direct rootless Xwayland/xwayland-satellite:

- Main UI could launch.
- Some flicker issues were avoided after disabling native Wayland.
- Popup menus appeared as centered floating windows instead of at the cursor.

niri forced fullscreen:

- Helped some size cases, but broke other windows and could produce bad screen origins.
- We observed startup failures where Ableton saw the display as offset, leading to blue/black startup screens.

Rootful Xwayland tiled by niri:

- Menu behavior was correct.
- The outer niri tile was smaller than the inner Xwayland screen, causing blur and click offsets.
- Even when launched with `-fakescreenfps 165`, rootful Xwayland exposed only about 60 Hz RandR modes on the tested machine.
- Ableton logged `UiFramework: Compositor timer engaged with nan Hz` on this path while the host UI still showed stale redraws.

Live forced OpenGL backend:

- `-_ForceOpenGlBackend` could reduce one class of Ableton redraw issue.
- With Serum 2.1.4, it caused black stale rectangles from Serum's editor path to spread into Ableton's host UI.
- The launcher now removes this flag before startup.

DXVK:

- Ableton's main UI and playback worked well.
- Serum 2 could show blue/blank or partially-redrawn plugin graphics.
- Setting `"Disable DirectComposition": true` and `"Disable Partial Redraw": true` helped DXVK, but fidelity was still worse than the patched D2D/DComp path.

Patched WineD3D/Vulkan:

- Live reached D3D device creation.
- Startup then hit a Visual C++ assertion in `wined3d.dll`.
- The assertion was `dlls/wined3d/cs.c:3261`, expression `flags & WINED3D_MAP_NOOVERWRITE`.

## Current Backend

The current best backend is niri's normal rootless Xwayland display plus a Wine virtual desktop, using patched Wine builtin D3D/DXGI/D2D/DComp with WineD3D's OpenGL renderer:

```bash
WINEPREFIX="$HOME/myWinePrefixes/abletonLive12" \
  "$HOME/.local/opt/wine-d2d1-11.11/bin/wine" reg add \
  'HKCU\Software\Wine\Direct3D' /v renderer /t REG_SZ /d opengl /f

DISPLAY=:1 WINE_D3D_CONFIG='csmt=0x1' \
  WINEDLLOVERRIDES='winemenubuilder.exe=d;winewayland.drv=d;d3d11,dxgi,d3d10core,d2d1,dcomp,dwrite,d3d9,d3d8=b' \
  "$HOME/.local/opt/wine-d2d1-11.11/bin/wine" explorer /desktop=AbletonLive12,2560x1440 \
  "C:\ProgramData\Ableton\Live 12 Suite\Program\Ableton Live 12 Suite.exe"
```

The key change from the earlier rootful Xwayland path is using the compositor's normal Xwayland display. On the tested Acer XB271HU, niri's normal Xwayland display exposed the physical output as `2560x1440@164.90`; rootful Xwayland still exposed about 60 Hz RandR modes to X11/Windows applications even with `-fakescreenfps 165`. Custom `xrandr` 165 Hz modelines on the rootful fallback were not durable.

For this stack, Ableton's `Options.txt` should not contain `-_ForceOpenGlBackend`. The Vulkan renderer asserted with this Wine path, and forcing Live's own OpenGL backend made Serum 2 editor redraw corruption spread into Ableton's host UI.

Current redraw-stability testing keeps Ableton's `-_Feature.UseGpuRenderer`
flag enabled. Disabling Live's GPU renderer made the constant redraw issue
worse. CSMT is the active test variable: the launcher currently defaults to
`WINE_D3D_CONFIG=csmt=0x1`, and `LIVE_WINE_D3D_CONFIG=csmt=0x0 live` forces
the older CSMT-off path.

Ableton's `-DontCombineAPCs` option is enabled because both Ableton's
`Options.txt` documentation and Wine-NSPA's Ableton Live 11/12 notes identify it
as relevant to Live's CPU/thread behavior under Wine. The launcher also uses
`chrt -r` for Wine when realtime scheduling is available. The rootful Xwayland
fallback also starts Xwayland under `chrt -r`, matching Wine-NSPA's
recommendation to reduce lock contention.

WineASIO can be registered and visible while Ableton still chooses `MME/DirectX`.
When that happens, Ableton logs high buffers such as `8192/4096` samples and
high total latency. Select `ASIO` plus `WineASIO Driver` in Live's audio
preferences; do not assume WineASIO is active from registration alone.

Serum 2 prefs should contain:

```json
{
    "Disable DirectComposition": false,
    "Disable Partial Redraw": false,
    "Default Overview Type Is 3D": false
}
```

## Required niri Behavior

The rootless Wine virtual desktop should be floating and output-sized. The rootful Xwayland fallback should also be floating when that fallback is used:

```kdl
window-rule {
    match app-id=r#"(?i)^(explorer\.exe|ableton live 12 suite\.exe)$"# title=r#"(?i)^(AbletonLive12|.*Ableton Live 12 Suite.*)$"#
    open-floating true
    draw-border-with-background false
    geometry-corner-radius 0
    clip-to-geometry false
}
window-rule {
    match app-id="org.freedesktop.Xwayland" title=r#"^Xwayland on :[0-9]+$"#
    open-floating true
    draw-border-with-background false
    geometry-corner-radius 0
    clip-to-geometry false
}
```

Do not force `open-fullscreen true` for this path.

## WebView2 Fix

Ableton starts WebView2. With global DXVK overrides, WebView2 can load DXVK and call an unsupported composition path:

```text
DxgiFactory::CreateSwapChainForComposition: Not implemented
```

The working fix forces WebView2 to Wine builtin DLLs:

```bash
wine reg add 'HKCU\Software\Wine\AppDefaults\msedgewebview2.exe\DllOverrides' /v d3d11 /t REG_SZ /d builtin /f
wine reg add 'HKCU\Software\Wine\AppDefaults\msedgewebview2.exe\DllOverrides' /v dxgi /t REG_SZ /d builtin /f
wine reg add 'HKCU\Software\Wine\AppDefaults\msedgewebview2.exe\DllOverrides' /v d2d1 /t REG_SZ /d builtin /f
```

The launcher also sets:

```bash
WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--disable-gpu --disable-gpu-compositing --disable-direct-composition --disable-accelerated-2d-canvas"
```

## Verification Checks

A good launch had these properties:

- niri reported the Wine virtual desktop floating at the output size.
- `DISPLAY=:1 xrandr` reported the physical output as `2560x1440@164.90`.
- The rootful Xwayland fallback may still report about 60 Hz even when launched with `-fakescreenfps 165`.
- Ableton log reported `Init: Screen at +0+0: 2560x1440, scale 1`.
- Ableton log reached `Default App: End InitApplication` and `Live App: End Init`.
- Ableton log should report clean startup. If it logs `GPU Renderer: OnAlways`, the host UI is using Live's GPU renderer.
- CSMT is currently tested with `WINE_D3D_CONFIG=csmt=0x1`; use `LIVE_WINE_D3D_CONFIG=csmt=0x0 live` to compare the older CSMT-off path.
- Ableton `Options.txt` should contain `-DontCombineAPCs`.
- `ps` should show realtime scheduling for the launched Wine processes when `chrt` is permitted.
- Right-click on a clip slot opened the context menu at the clip slot.
- Moving the pointer into that menu highlighted menu items.
- Serum 2 opened with usable graphics instead of a blue/blank surface.
- Serum 2 did not leave black stale rectangles across Ableton when `-_ForceOpenGlBackend` was absent.
