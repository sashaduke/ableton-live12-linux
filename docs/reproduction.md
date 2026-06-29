# Reproduction Notes

These notes capture the path that worked for Ableton Live 12.4.2 Suite on niri on June 29, 2026.

## Machine

- Ableton Live 12.4.2 Suite
- Wine staging 11.11
- niri 26.04
- AMD Radeon RX 7900 GRE, RADV
- `2560x1440` output at scale `1.0`
- Wine prefix: `~/myWinePrefixes/abletonLive12`
- Ableton executable: `C:\ProgramData\Ableton\Live 12 Suite\Program\Ableton Live 12 Suite.exe`

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

## Final Backend

The working backend is rootful Xwayland plus a Wine virtual desktop:

```bash
Xwayland :20 -ac -terminate -geometry 2560x1440 -br -decorate
DISPLAY=:20 wine explorer /desktop=AbletonLive12,2560x1440 \
  "C:\ProgramData\Ableton\Live 12 Suite\Program\Ableton Live 12 Suite.exe"
```

The installer generalizes the display number and geometry.

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

The working fix keeps DXVK for Ableton but forces WebView2 to Wine builtin DLLs:

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
- Ableton log reported `Init: Screen at +0+0: 2560x1440, scale 1`.
- Ableton log reached `Default App: End InitApplication` and `Live App: End Init`.
- Ableton log reported `GPU Renderer: OnAlways`.
- DXVK reported the main Ableton buffer as `2552x1387`, the client area inside the Wine desktop decorations.
- Right-click on a clip slot opened the context menu at the clip slot.
- Moving the pointer into that menu highlighted menu items.
- No `msedgewebview2_d3d11.log` was created after applying WebView2 app-default overrides.
