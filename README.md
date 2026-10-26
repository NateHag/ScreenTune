# ScreenTune

A small macOS menu bar app for screen color and auto-brightness.

- **Saturation** (30%–200%), through a custom display color profile. ColorSync does the math, so there is no lag.
- **Warmth, contrast, mid tones, extra dim, red/green/blue**, through the display gamma table.
- **Auto-brightness with your own curve.** It reads the light sensor and sets the built-in display's backlight. You drag points to set how bright the screen is at each light level. Brightness-key changes are kept as an offset.

Quitting puts the screen back as it was, including your own color profile.

## Build

Needs only the Xcode Command Line Tools (not full Xcode).

```bash
./build.sh
open build/ScreenTune.app
```

`ScreenTune --selftest` checks each part on real hardware and then restores everything.

## Notes

- Uses private Apple APIs (DisplayServices for brightness, IOHIDEventSystemClient for the light sensor). Not for the App Store, and a macOS update can break it.
- Turn off **System Settings > Displays > Automatically adjust brightness** when you use the custom curve.
- Each saturation change makes every app redraw once.
- Tested on a MacBook Air (M1), macOS 27.
