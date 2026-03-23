#!/usr/bin/env bash
set -euo pipefail

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-dir)
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

BASE="${HOME}/.local/ultra_dictation"
BIN_DIR="${HOME}/.bin"
LAUNCH_AGENT_FILE="${HOME}/Library/LaunchAgents/local.ultra.dictation.plist"
KARABINER_JSON="${HOME}/.config/karabiner/karabiner.json"
KARABINER_ASSET_FILE="${HOME}/.config/karabiner/assets/complex_modifications/ultra-dictation.json"

printf 'off\n' > "${BASE}/active.state" 2>/dev/null || true
uid="$(id -u)"
launchctl bootout "gui/${uid}" "${LAUNCH_AGENT_FILE}" >/dev/null 2>&1 || true

rm -f "${LAUNCH_AGENT_FILE}"
rm -f "${BIN_DIR}/dictation-start" "${BIN_DIR}/dictation-stop" "${BIN_DIR}/dictation-toggle"
rm -f "${KARABINER_ASSET_FILE}"

if [[ -f "${KARABINER_JSON}" ]]; then
  python3 - "${KARABINER_JSON}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())
profiles = data.get("profiles", [])
if profiles:
    profile = profiles[0]
    complex_mods = profile.get("complex_modifications", {})
    rules = complex_mods.get("rules", [])
    complex_mods["rules"] = [
        r for r in rules if not str(r.get("description", "")).startswith("Ultra Dictation Toggle")
    ]
    path.write_text(json.dumps(data, indent=4) + "\n")
PY
fi

rm -rf "${BASE}"

echo "Ultra Dictation removed."
