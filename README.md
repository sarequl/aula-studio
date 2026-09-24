# Aula Studio

Native macOS control for AULA keyboards with a screen. Put GIFs, images, video clips or text on the display, keep a library of them, sync the screen clock, and set the key backlight. No drivers or kernel extensions; it talks to the keyboard through IOKit HID.

Supported: **AULA F108 Pro** (verified on hardware). Other models in the same line use the same command set with different USB ids and screen sizes; see [Adding a model](#adding-a-model).

The keyboard only accepts configuration over the USB cable with the mode switch set to wired. Bluetooth and the 2.4G dongle are input-only, and the vendor's own software has the same limitation.

## Install

Download `AulaStudio.zip` from the latest release, unzip, and drag `AulaStudio.app` to Applications. The app is unsigned, so on first launch right-click it and choose Open.

Or build it yourself:

```bash
./scripts/bundle.sh
```

That produces `dist/AulaStudio.app`. `swift build -c release` alone gives you the `aula` command-line tool at `.build/release/aula`.

## App

- **Screen**: drop a GIF, PNG, JPEG, WebP, MP4 or MOV, pick fill/fit/stretch and speed, send.
- **Library**: everything you've saved, with thumbnails and one-click resend, plus built-in gradients and solid colors.
- **Text**: static or scrolling text rendered on the Mac, any system font and color.
- **Lighting**: the 20 backlight effects with color, brightness, speed and direction, applied live.
- **Clock**: syncs the screen clock to the Mac, by default every time you plug the keyboard in.

## CLI

```bash
aula status                                   # which model, wired / wireless / not found
aula clock                                    # set the screen clock to now
aula screen cat.gif                           # upload (fill/crop by default)
aula screen clip.mp4 fit --fps 12 --speed 1.5
aula screen --color FF00FF                    # solid color
aula text "hello" --scroll 120 --color 00E5FF # scrolling marquee
aula gradient aurora                          # animated gradient
aula preview cat.gif out.gif                  # what the screen will show, no keyboard needed
aula light breath 00C8FF --brightness 5 --speed 2
aula light spectrum --rainbow
aula modes
```

Add `-v` to print the HID traffic.

## How it works

The screen is 240×135 RGB565. An upload is a 256-byte header (frame count, then one byte per frame of delay in 20 ms units) followed by raw frames, padded to 4 KB pages. Pages go out as 4096-byte HID output reports on the vendor interface with usage page 0xFF68, and the keyboard acknowledges each one with a 64-byte input report. Control commands (begin `04 18`, image header `04 72`, apply `04 02`, lighting `04 13`, clock `04 28`) are 64-byte feature reports on the 0xFF13 interface; every one must be read back or the firmware drops the next command.

**The firmware does no bounds checking.** The F108 Pro's flash slot holds 141 frames. Writing more spills into the region holding the knob-menu graphics and destroys them, with no known recovery. `AulaKit` refuses anything over the profile's limit and thins longer media evenly while keeping the loop duration, so this cannot happen through this tool. Never raise `maxFrames` in a profile without a verified source.

A full 141-frame upload is 2231 pages and takes about 5.5 minutes. The keyboard then shows its own progress bar while it commits to flash. Don't unplug during either phase.

## Adding a model

Add a `KeyboardProfile` in [KeyboardProfile.swift](Sources/AulaKit/KeyboardProfile.swift): wired VID/PID, wireless VID/PID if any, screen size, and `maxFrames` taken from the `gif_maxframes` value in the vendor software's `config.xml` for that model. Mark it `verified: false` until someone has run an upload on real hardware. `ioreg -p IOUSB -l | grep -A3 -i aula` shows the USB ids.

## Layout

- `Sources/AulaKit` — profiles, protocol, IOKit transport, media decoding, generators, library store
- `Sources/aula` — command-line tool
- `Sources/AulaStudio` — SwiftUI app
- `scripts/bundle.sh` — builds the `.app`; `scripts/make-icon.swift` regenerates the icon

## Credits

Protocol reverse engineering: [parsiya/f108-pro](https://github.com/parsiya/f108-pro) (Ghidra work on the Windows driver plus hardware verification, including the flash-overflow finding above).

MIT licensed.
