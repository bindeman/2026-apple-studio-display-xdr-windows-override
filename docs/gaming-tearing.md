# Gaming Tearing

The tested display mode is high bandwidth:

```text
5120x2880
120 Hz / 120.04 Hz
HDR / Advanced Color optional
tiled MST + DSC over Thunderbolt / USB4
```

If a game tears while V-Sync is enabled, treat it as a frame-pacing path issue first, not as proof that the display mode is bad.

Apple's Studio Display XDR technology overview says the panel supports Adaptive Sync at full 5K and uses local frame scheduling to handle varying frame rates. On Windows, this repo can expose the transport mode and help test fixed refresh/HDR state, but it does not yet control Apple's macOS-only display optimization modes or reference-mode latency/quality choices.

## First Checks

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-StudioXdrStatus.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Get-StudioXdrColorStatus.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Get-StudioXdrGamingStatus.ps1
```

Verify:

```text
Resolution: 5120 x 2880
Refresh:    120 Hz or 120.04 Hz
Bits:       8 bpc SDR or 10 bpc HDR path
```

`Get-StudioXdrColorStatus.ps1` reads the active DisplayConfig path directly. This is more reliable than `Win32_VideoController` on tiled/Thunderbolt displays.

`Get-StudioXdrGamingStatus.ps1` combines that DisplayConfig read with a 5K120 mode test, GPU driver details, `nvidia-smi` output when available, Windows graphics registry hints, and an initial frame-cap recommendation. The root launcher is:

```text
Check-Gaming.cmd
```

To test whether Windows accepts the 5K120 mode without changing anything:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Set-StudioXdrDisplayMode.ps1 -RefreshRate 120 -TestOnly
```

To switch the active Studio XDR target:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Set-StudioXdrDisplayMode.ps1 -RefreshRate 60
powershell -ExecutionPolicy Bypass -File .\scripts\Set-StudioXdrDisplayMode.ps1 -RefreshRate 120
```

If the right side of the display becomes pixelated, switch to `60 Hz`, apply, then switch back to `120 Hz` or `120.04 Hz`. That forces link retraining.

## NVIDIA Settings To Test

In NVIDIA Control Panel, test these per game:

```text
Monitor Technology: G-SYNC Compatible, if available
Vertical Sync: On
Max Frame Rate: 117 FPS for 120 Hz, or 118 FPS for 120.04 Hz
Low Latency Mode: On, not Ultra, for initial testing
Power management mode: Prefer maximum performance
```

In the game:

```text
Exclusive fullscreen: test both on and off
V-Sync: on if using NVIDIA V-Sync + frame cap
Frame generation: off while diagnosing tearing
HDR: test off, then on
```

If the game has a built-in frame limiter, prefer it over an external limiter. If it does not, use NVIDIA's max frame rate cap.

## Windows Settings To Test

```text
Settings > System > Display > Graphics > Default graphics settings
```

Test:

```text
Variable refresh rate: on
Optimizations for windowed games: on, then off if tearing persists
Hardware-accelerated GPU scheduling: on, then off if tearing persists
Dynamic refresh rate: off while diagnosing
```

Dynamic refresh rate looked stable locally, but it adds another variable. Use fixed `120 Hz` or `120.04 Hz` while testing games.

## HDR Interaction

HDR currently works through Windows Advanced Color, but this is not the same as Apple-native reference-mode support.

If tearing or frame pacing changes when HDR is on:

1. Disable HDR with `Disable-HDR.cmd`.
2. Test the same game at `5120x2880 @ 120 Hz`.
3. Re-enable HDR with `Enable-HDR.cmd`.
4. Test again.

This tells us whether the issue is the transport mode generally or the HDR swapchain path specifically.

## What To Capture

For useful bug reports, capture:

```text
Game title and API: DirectX 11 / DirectX 12 / Vulkan
Fullscreen mode: exclusive / borderless / windowed
Refresh selected: 120 Hz / 120.04 Hz / Dynamic
HDR: on / off
G-SYNC or VRR: on / off
Frame cap: none / 117 / 118 / other
Whether tearing is full-screen or only one tile/side
```

If tearing happens only on one side of the display, that points toward tiled display composition, DSC, or link training. If it happens across the whole display, it is more likely normal game/driver frame pacing.
