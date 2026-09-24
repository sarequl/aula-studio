# AULA F108 Pro for macOS

Native macOS control for the AULA F108 Pro keyboard: put GIFs, images and video clips on its screen, sync the screen clock, and set the key backlight. No drivers, no kernel extensions; it talks to the keyboard through IOKit HID.

The vendor protocol only answers over the USB cable with the mode switch set to wired. Bluetooth and the 2.4G dongle are input-only.

## Build

```bash
swift build -c release
```

Produces `.build/release/aula` (CLI) and `.build/release/AulaStudio` (app).

## App

```bash
.build/release/AulaStudio
```

Drop a GIF, PNG, JPEG, WebP, MP4 or MOV onto the screen preview, pick fill/fit/stretch and speed, and hit Send. The app polls for the keyboard and, by default, syncs the clock every time you plug it in.

## CLI

```bash
aula status                                   # wired / wireless / not found
aula clock                                    # set the screen clock to now
aula screen cat.gif                           # upload (fill/crop by default)
aula screen clip.mp4 fit --fps 12 --speed 1.5
aula screen --color FF00FF                    # solid color, quick sanity test
aula preview cat.gif out.gif                  # see what the screen will show, no keyboard needed
aula light breath 00C8FF --brightness 5 --speed 2
aula light spectrum --rainbow
aula modes
```

Add `-v` to print the HID traffic.

## What the keyboard accepts

The screen is 240×135, RGB565. An upload is a 256-byte header (frame count, then one byte per frame of delay in 20 ms units) followed by raw frames, padded to 4 KB pages. Pages go out as 4096-byte HID output reports on the vendor interface (usage page 0xFF68) and each one is acknowledged with a 64-byte input report. Control commands (begin `04 18`, image header `04 72`, apply `04 02`, lighting `04 13`, clock `04 28`) are 64-byte feature reports on the other vendor interface (0xFF13); every one must be read back or the firmware drops the next command.

**The firmware does no bounds checking.** Its flash slot holds 141 frames. Writing more spills into the region holding the knob-menu graphics and destroys them, with no known way back. `AulaKit` refuses anything over 141 frames and thins longer media evenly while keeping the loop duration, so this cannot happen through this tool. Don't raise `F108.maxFrames`.

A full 141-frame upload is 2231 pages and takes about 2.5 minutes. The keyboard then shows its own progress bar while it commits to flash. Don't unplug during either phase.

## Layout

- `Sources/AulaKit` — protocol, IOKit transport, media decoding and RGB565 encoding
- `Sources/aula` — command-line tool
- `Sources/AulaStudio` — SwiftUI app

## Credits

Protocol reverse engineering: [parsiya/f108-pro](https://github.com/parsiya/f108-pro) (Ghidra work on the Windows driver plus hardware verification, including the flash-overflow finding above).
