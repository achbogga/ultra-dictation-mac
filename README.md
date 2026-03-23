# Ultra Dictation Mac

`Ultra Dictation Mac` packages a Logitech `G1 -> F13 -> Karabiner -> local speech-to-text` workflow for macOS.

It installs:

- A resident launchd helper that stays idle until dictation is toggled on
- A native HUD indicator built with AppKit and SF Symbols
- Shell commands in `~/.bin` for start, stop, and toggle
- A Karabiner rule for `F13`

## What It Does

1. Logitech software maps `G1` to `F13`
2. Karabiner maps `F13` to `~/.bin/dictation-toggle`
3. The helper records while dictation is active
4. When you toggle off, the helper transcribes the captured session and pastes it into the focused app

## Requirements

- macOS
- `python3`
- Apple Command Line Tools with `swiftc`
- Karabiner-Elements if you want the included `F13` rule
- Logitech Options+ or G Hub if you want `G1` to emit `F13`

## Install

Shell installer:

```bash
sh install.sh
```

Build the installer app:

```bash
sh scripts/build_app.sh
open dist/UltraDictationInstaller.app
```

## Notes

- The installer tries to patch `~/.config/karabiner/karabiner.json` if it exists.
- It also installs a standalone Karabiner asset JSON file under `~/.config/karabiner/assets/complex_modifications/`.
- If your `G1` key already emits `F13`, the default install should be enough.
- If your focused app still does not receive pasted text, the clipboard should still contain the transcription.

## Repo Layout

- `templates/`: helper sources and installed script templates
- `install.sh`: shell installer
- `uninstall.sh`: shell uninstaller
- `app/`: native installer app source
- `scripts/build_app.sh`: builds the `.app` bundle into `dist/`
