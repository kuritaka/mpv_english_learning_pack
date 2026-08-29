# mpv English Learning Setup

## Purpose

This setup is designed for the following layout and workflow:

- Left 50%: video
- Right 50%: subtitle learning panel
- Right panel:
  - 2 previous subtitle lines
  - 1 current subtitle line (highlighted)
  - 2 next subtitle lines
- Mouse controls:
  - Left click: play / pause
  - Left double-click: fullscreen
  - Right click: uosc menu
  - Mouse wheel: seek forward / backward 5 seconds in the video area
- uosc + thumbfast:
  - Mouse-friendly playback controls
  - Seek bar
  - Thumbnail preview when hovering over the seek bar
- mpv saves the playback position when you exit

---

## Easiest Installation Method

If you use the Windows ZIP build of mpv, copy the contents of this ZIP into the directory that contains **mpv.exe**.

After copying:

```text
mpv/
├─ mpv.exe
├─ install_addons.ps1
└─ portable_config/
   ├─ mpv.conf
   ├─ input.conf
   ├─ scripts/
   │  └─ english-subs.lua
   └─ script-opts/
      └─ english-subs.conf
```

Important:

Place the `portable_config` directory itself at the same level as `mpv.exe`.

---

## Installing uosc / thumbfast

uosc and thumbfast are external projects that are updated independently, so fixed versions are not included in this ZIP.

Open PowerShell in the directory that contains `mpv.exe`, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install_addons.ps1
```

Or, directly from PowerShell:

```powershell
.\install_addons.ps1
```

After installation, uosc and thumbfast will be added under `portable_config`.

---

## Video and Subtitle Files

Example:

```text
Friends.S01E01.mp4
Friends.S01E01 English study.srt
```

`english-subs.lua` is designed to find `.srt` files whose names start with the video filename.

This makes it easier to add notes to subtitle filenames than with MPC-BE.

For example:

```text
Friends.S01E01.mp4
Friends.S01E01 English study revised.srt
```

is also a valid candidate.

If multiple SRT files start with the same video filename, the script generally prefers the file with the shorter filename.

If you regularly use subtitles in multiple languages, you can later add rules such as prioritizing English subtitles.

---

## English Learning Key Bindings

`Ctrl + Left Arrow`  
Move to the previous subtitle cue.

`Ctrl + Right Arrow`  
Move to the next subtitle cue.

`R`  
Replay the current subtitle from its beginning.

`S`  
Toggle the subtitle learning panel on the right side.

`Space`  
Play / pause.

`Left Arrow / Right Arrow`  
Seek backward / forward 5 seconds.

`Up Arrow / Down Arrow`  
Seek forward / backward 10 seconds.

`Shift + Left Arrow / Shift + Right Arrow`  
Seek backward / forward 1 second.

`[ / ]`  
Decrease / increase playback speed by 0.1.

`Backspace`  
Reset playback speed to 1.0.

---

## How the Subtitle Panel Avoids Covering the Video

In `mpv.conf`:

```ini
video-margin-ratio-right=0.50
```

This reserves the right 50% of the window so the video is not displayed there.

`english-subs.lua` renders the subtitle learning panel inside that reserved area.

---

## If Subtitles Are Not Displayed

Check the following:

1. The subtitle file uses the `.srt` extension.
2. The MP4 and SRT files are in the same directory.
3. The SRT filename starts with the video filename.

Example:

```text
OK:
ABC Episode 01.mp4
ABC Episode 01 English study.srt
```

```text
NG:
ABC Episode 01.mp4
English study Episode 01.srt
```

---

## Notes

- UTF-8 is recommended for SRT files.
- If an SRT file contains extensive formatting, the learning view removes most special styling for readability.
- The current subtitle changes based on the SRT start and end timestamps.
- During gaps between subtitle cues, the next subtitle is treated as the current candidate.
