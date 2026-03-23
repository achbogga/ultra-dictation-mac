# Ultra Dictation Mac

`Ultra Dictation Mac` packages a Logitech or keyboard shortcut -> Karabiner -> local speech-to-text workflow for macOS.

It installs:

- A resident launchd helper that stays idle until dictation is toggled on
- A native HUD indicator built with AppKit and SF Symbols
- Shell commands in `~/.bin` for start, stop, and toggle
- A Karabiner rule for a user-configurable `key_code` (default: `f13`)

## What It Does

1. Your keyboard utility maps a button or key to a Karabiner `key_code` such as `f13`
2. Karabiner maps that key to `~/.bin/dictation-toggle`
3. The helper records while dictation is active
4. When you toggle off, the helper transcribes the captured session and pastes it into the focused app

## Requirements

- macOS
- `python3`
- Apple Command Line Tools with `swiftc`
- Karabiner-Elements if you want the included hotkey rule
- Logitech Options+ or G Hub if you want a Logitech key to emit your chosen hotkey

## Install

Shell installer:

```bash
sh install.sh
```

Start the helper automatically at login:

```bash
sh install.sh --enable-on-boot
```

Install without starting it at login:

```bash
sh install.sh --disable-on-boot
```

Choose a custom hotkey instead of the default `f13`:

```bash
sh install.sh --hotkey right_command
```

Build the installer app:

```bash
sh scripts/build_app.sh
open dist/UltraDictationInstaller.app
```

The native installer app includes both a launch-at-login checkbox and a field for the Karabiner `key_code`.

## Notes

- The installer tries to patch `~/.config/karabiner/karabiner.json` if it exists.
- It also installs a standalone Karabiner asset JSON file under `~/.config/karabiner/assets/complex_modifications/`.
- The default hotkey is `f13`. Override it with `--hotkey <karabiner_key_code>` or in the installer app.
- Launch-at-login is optional. The default install keeps boot startup off unless you pass `--enable-on-boot` or tick the checkbox in the installer app.
- If your `G1` key already emits `F13`, the default install should be enough.
- The hotkey value must be a valid Karabiner `key_code` such as `f13`, `right_command`, or `page_down`.
- If your focused app still does not receive pasted text, the clipboard should still contain the transcription.

## Repo Layout

- `templates/`: helper sources and installed script templates
- `install.sh`: shell installer
- `uninstall.sh`: shell uninstaller
- `app/`: native installer app source
- `scripts/build_app.sh`: builds the `.app` bundle into `dist/`
