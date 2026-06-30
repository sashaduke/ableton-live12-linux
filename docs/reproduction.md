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

Rootless Xwayland/xwayland-satellite:

- Main UI could launch.
- Some flicker issues were avoided after disabling native Wayland.
- Popup menus appeared as centered floating windows instead of at the cursor.

niri forced fullscreen:

- Helped some size cases, but broke other windows and could produce bad screen origins.
- We observed startup failures where Ableton saw the display as offset, leading to blue/black startup screens.

Rootful Xwayland tiled by niri:

- Menu behavior was correct.
- The outer niri tile was smaller than the inner Xwayland screen, causing blur and click offsets.

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

## Final Backend

The working backend is rootful Xwayland plus a Wine virtual desktop, using patched Wine builtin D3D/DXGI/D2D/DComp with WineD3D's OpenGL renderer:

```bash
WINEPREFIX="$HOME/myWinePrefixes/abletonLive12" \
  "$HOME/.local/opt/wine-d2d1-11.11/bin/wine" reg add \
  'HKCU\Software\Wine\Direct3D' /v renderer /t REG_SZ /d opengl /f

Xwayland :20 -ac -terminate -geometry 2560x1440 -fakescreenfps 165 -br -decorate
DISPLAY=:20 WINE_D3D_CONFIG='csmt=0x0' vblank_mode=0 \
  WINEDLLOVERRIDES='winemenubuilder.exe=d;winewayland.drv=d;d3d11,dxgi,d3d10core,d2d1,dcomp,dwrite,d3d9,d3d8=b' \
  "$HOME/.local/opt/wine-d2d1-11.11/bin/wine" explorer /desktop=AbletonLive12,2560x1440 \
  "C:\ProgramData\Ableton\Live 12 Suite\Program\Ableton Live 12 Suite.exe"
```

The installer generalizes the display number, geometry, and refresh rate. On the tested Acer XB271HU, niri reported the physical output at `2560x1440@165`; rootful Xwayland still exposed 60 Hz RandR modes to X11/Windows applications even with `-fakescreenfps 165`. Custom `xrandr` 165 Hz modelines were not durable, so the launcher also sets `vblank_mode=0` for the WineD3D/OpenGL stack.

For this stack, Ableton's `Options.txt` should contain `-_Feature.UseGpuRenderer` and should not contain `-_ForceOpenGlBackend`. The Vulkan renderer asserted with this Wine path, and forcing Live's own OpenGL backend made Serum 2 editor redraw corruption spread into Ableton's host UI.

The launcher should also set `WINE_D3D_CONFIG=csmt=0x0`. Without that, Ableton's host UI can leave tracers or wait for another click/key event before repainting.

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

The rootful Xwayland window must be floating and exactly output-sized:

```kdl
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

- niri reported `org.freedesktop.Xwayland`, floating, `window_size [2560,1440]`, `tile_pos [0,0]`.
- Nested `xrandr` reported `XWAYLAND0 connected 2560x1440+0+0`.
- Nested `xrandr` may still report about 60 Hz; the launcher mitigates this with `vblank_mode=0`.
- Ableton log reported `Init: Screen at +0+0: 2560x1440, scale 1`.
- Ableton log reached `Default App: End InitApplication` and `Live App: End Init`.
- Ableton log should report clean startup. If it logs `GPU Renderer: OnAlways`, the host UI is using Live's GPU renderer; this is preferred for avoiding stale Ableton UI redraws under WineD3D/OpenGL.
- Ableton's own UI repainted immediately after hotkeys with `WINE_D3D_CONFIG=csmt=0x0`.
- Right-click on a clip slot opened the context menu at the clip slot.
- Moving the pointer into that menu highlighted menu items.
- Serum 2 opened with usable graphics instead of a blue/blank surface.
- Serum 2 did not leave black stale rectangles across Ableton when `-_ForceOpenGlBackend` was absent.
