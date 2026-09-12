# Roadmap

This project aims to make the 2026 Apple Studio Display XDR feel as close as possible to first-party hardware on Windows.

## Working Now

- Native-mode EDID override for Studio Display XDR.
- HDR / Advanced Color enable and disable scripts.
- Studio Display XDR brightness control over Apple USB HID.
- Root-level setup launcher:
  - Opens install/repair, uninstall, control panel, support report, and README actions from one executable.
  - Elevates only for installer/uninstaller flows.
- Guided installer entry point:
  - Detects the Studio Display XDR identity.
  - Installs or refreshes the EDID override.
  - Offers HDR enablement.
  - Tests and can optionally apply 5120x2880 @ 120 Hz.
  - Verifies the brightness HID path.
  - Opens the control panel.
- Guided uninstaller entry point for startup entries, shortcuts, generated profile association, and optional EDID override cleanup.
- Native Windows control panel:
  - Studio Display XDR connection state.
  - Brightness slider.
  - Signal, refresh-rate, HDR, and bits-per-channel status.
  - One-click display optimization for 5K120 plus HDR / Advanced Color.
  - Manual 60 Hz / 120 Hz switching.
  - Manual HDR toggle.
  - Generated Display P3 color-profile install control.
  - Auto-brightness with Windows ALS, experimental `MI_08`, and camera fallback paths.
  - Persistent auto-brightness minimum, maximum, and response controls.
  - Diagnostics report generation.
  - Open at login preference that starts the app minimized.
- Self-contained release ZIP with a compiled WPF control panel and a setup launcher executable.
- Release ZIP verifier that checks the actual artifact for launchers, docs, EDID, color profile, app runtime files, and content signatures.
- GitHub issue templates for normal support reports and ambient-sensor experiments.

Current feature status is tracked in [support-matrix.md](support-matrix.md).
Release readiness is tracked in [release-checklist.md](release-checklist.md).

## Product Goals

### 1. Installer

Create a single guided installer that can:

- Check that the connected monitor is Studio Display XDR.
- Back up current monitor EDID data.
- Install the Studio Display XDR EDID override.
- Offer to enable HDR.
- Test and optionally apply 5120x2880 @ 120 Hz.
- Show ambient-sensor status and offer advanced MI_08 WinUSB/libusb experiments only when explicitly confirmed.
- Install or launch the Studio Display XDR control panel.
- Provide a clear uninstall/recovery path.

### 2. Display Control Panel

Keep the control panel focused and predictable:

- Studio Display XDR only.
- Brightness slider with direct HID write/readback.
- Connection state for USB4 / Thunderbolt HID control.
- Startup preference with minimized launch.
- Future: optional keyboard brightness shortcuts.
- Future: optional tray presence if users want background controls.

### 3. Auto Brightness

Studio Display XDR `05AC:1116` does not currently expose a working ambient light sensor to Windows.

Implemented source priority:

- Enumerate Windows ambient light sensors and prefer Apple/display-looking sensors when present.
- Use the experimental Studio Display XDR `MI_08` connector if it is bound and returns packets.
- Use the experimental SDBC-style libusb path if an exact MI_08 filter exposes endpoint `0x89`.
- Use the Studio Display Camera as an opt-in rough ambient-light proxy.

Still worth researching:

- Validate Pro Display XDR ambient light sensor reuse when a Pro Display XDR is connected at the same time.
- Improve camera fallback calibration and black-frame warm-up behavior.
- Sign and simplify the `MI_08` connector flow if the interface proves useful.

### 4. Color And HDR

Current state:

- EDID advertises HDR metadata, wide color, and the Studio XDR identity.
- Windows Advanced Color can be enabled through DisplayConfig APIs.
- A generated Display P3 D65 gamma 2.2 baseline ICC profile is bundled.
- Apple reference modes and Apple-authored ICC/ICM profiles are not replicated yet.
- Apple's Studio Display XDR technology overview says non-macOS hosts use EDID/DisplayID and are color-space-limited to P3 even when BT.2020 capability is reported.

Next steps:

- Extract and catalog any Apple color profiles from Apple/Boot Camp packages.
- Compare Studio Display XDR EDID primaries and HDR luminance metadata against Apple specs.
- Validate the generated Display P3 profile with calibration software and measured panel data.
- Document Windows Color Management setup for users who want a custom ICC/ICM workflow.
- Avoid claiming full Apple reference-mode parity until measured.

### 5. Pro Display XDR Cross-Reference

Pro Display XDR remains useful for research:

- Its brightness HID path works in SDR.
- HDR/reference behavior can override visible brightness.
- Its ambient light sensors are exposed to Windows as standard HID Ambient Light Sensor devices.

This repo should stay focused on Studio Display XDR. Pro Display XDR behavior can inform future Studio work, but should not complicate the main app.

## Release Criteria

A release should include:

- `StudioDisplayXdr.exe`
- `Studio-Display-XDR.cmd`
- EDID override installer and uninstaller
- HDR enable/disable launchers
- Brightness scripts for diagnostics
- Support report generation from the app
- Generated Display P3 baseline profile and profile installer
- Guided uninstaller
- Release package verifier
- Recovery documentation
- Clear notes about experimental auto-brightness sources and unsupported reference modes
