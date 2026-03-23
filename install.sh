#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${ROOT_DIR}"
BOOT_ON_LOGIN="${ULTRA_DICTATION_BOOT_ON_LOGIN:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-dir)
      RESOURCE_DIR="$2"
      shift 2
      ;;
    --enable-on-boot)
      BOOT_ON_LOGIN="1"
      shift
      ;;
    --disable-on-boot)
      BOOT_ON_LOGIN="0"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

TEMPLATE_DIR="${RESOURCE_DIR}/templates"
REQ_FILE="${RESOURCE_DIR}/requirements.txt"
BASE="${HOME}/.local/ultra_dictation"
BIN_DIR="${HOME}/.bin"
CFG_DIR="${HOME}/.config/ultra_dictation"
LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
LAUNCH_AGENT_FILE="${LAUNCH_AGENT_DIR}/local.ultra.dictation.plist"
KARABINER_DIR="${HOME}/.config/karabiner"
KARABINER_JSON="${KARABINER_DIR}/karabiner.json"
KARABINER_ASSET_DIR="${KARABINER_DIR}/assets/complex_modifications"
KARABINER_ASSET_FILE="${KARABINER_ASSET_DIR}/ultra-dictation.json"
VENV_DIR="${BASE}/venv"
PIP_BIN="${VENV_DIR}/bin/pip"
SWIFTC_BIN="$(xcrun --find swiftc 2>/dev/null || true)"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd python3
require_cmd launchctl

if [[ -z "${SWIFTC_BIN}" ]]; then
  echo "swiftc was not found. Install Apple Command Line Tools first." >&2
  exit 1
fi

if [[ "${BOOT_ON_LOGIN}" != "0" && "${BOOT_ON_LOGIN}" != "1" ]]; then
  echo "ULTRA_DICTATION_BOOT_ON_LOGIN must be 0 or 1." >&2
  exit 1
fi

mkdir -p "${BASE}" "${BIN_DIR}" "${CFG_DIR}" "${LAUNCH_AGENT_DIR}" "${KARABINER_ASSET_DIR}"

if [[ ! -d "${VENV_DIR}" ]]; then
  python3 -m venv "${VENV_DIR}"
fi

"${PIP_BIN}" install --upgrade pip setuptools wheel
"${PIP_BIN}" install -r "${REQ_FILE}"

install -m 0644 "${TEMPLATE_DIR}/engine.py" "${BASE}/engine.py"
install -m 0644 "${TEMPLATE_DIR}/indicator.swift" "${BASE}/indicator.swift"
install -m 0755 "${TEMPLATE_DIR}/dictation-start" "${BIN_DIR}/dictation-start"
install -m 0755 "${TEMPLATE_DIR}/dictation-stop" "${BIN_DIR}/dictation-stop"
install -m 0755 "${TEMPLATE_DIR}/dictation-toggle" "${BIN_DIR}/dictation-toggle"

if [[ ! -f "${CFG_DIR}/config" ]]; then
  install -m 0644 "${TEMPLATE_DIR}/config" "${CFG_DIR}/config"
fi

printf 'off\n' > "${BASE}/active.state"
"${SWIFTC_BIN}" "${BASE}/indicator.swift" -o "${BASE}/dictation-indicator"
chmod +x "${BASE}/dictation-indicator"

python3 - "${TEMPLATE_DIR}/local.ultra.dictation.plist.in" "${LAUNCH_AGENT_FILE}" "${HOME}" "${BOOT_ON_LOGIN}" <<'PY'
from pathlib import Path
import sys

template_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
home = sys.argv[3]
boot_on_login = sys.argv[4] == "1"
run_at_load = "<true/>" if boot_on_login else "<false/>"

content = template_path.read_text()
content = content.replace("__HOME__", home)
content = content.replace("__RUN_AT_LOAD__", run_at_load)
output_path.write_text(content)
PY
install -m 0644 "${TEMPLATE_DIR}/karabiner-ultra-dictation.json" "${KARABINER_ASSET_FILE}"

if [[ -f "${KARABINER_JSON}" ]]; then
  cp "${KARABINER_JSON}" "${KARABINER_JSON}.bak.$(date +%Y%m%d-%H%M%S)"
  python3 - "${KARABINER_JSON}" "${TEMPLATE_DIR}/karabiner-ultra-dictation.json" <<'PY'
import json
import sys
from pathlib import Path

karabiner_path = Path(sys.argv[1])
snippet_path = Path(sys.argv[2])

data = json.loads(karabiner_path.read_text())
snippet = json.loads(snippet_path.read_text())
rule = snippet["rules"][0]

profiles = data.get("profiles", [])
if profiles:
    profile = profiles[0]
    complex_mods = profile.setdefault("complex_modifications", {})
    rules = complex_mods.setdefault("rules", [])
    rules = [r for r in rules if r.get("description") != rule.get("description")]
    rules.insert(0, rule)
    complex_mods["rules"] = rules
    karabiner_path.write_text(json.dumps(data, indent=4) + "\n")
PY
fi

uid="$(id -u)"
launchctl bootout "gui/${uid}" "${LAUNCH_AGENT_FILE}" >/dev/null 2>&1 || true
if [[ "${BOOT_ON_LOGIN}" == "1" ]]; then
  launchctl bootstrap "gui/${uid}" "${LAUNCH_AGENT_FILE}"
  launchctl kickstart "gui/${uid}/local.ultra.dictation"
fi

cat <<EOF
Install complete.

Files installed:
  ${BASE}
  ${BIN_DIR}/dictation-start
  ${BIN_DIR}/dictation-stop
  ${BIN_DIR}/dictation-toggle
  ${LAUNCH_AGENT_FILE}
  Start helper on login: $( [[ "${BOOT_ON_LOGIN}" == "1" ]] && echo yes || echo no )

Karabiner:
  Asset file: ${KARABINER_ASSET_FILE}
  Primary config patched: $( [[ -f "${KARABINER_JSON}" ]] && echo yes || echo no )

Next:
  1. Map Logitech G1 to F13 in Logitech Options+ or G Hub
  2. Ensure Karabiner uses the installed "Ultra Dictation Toggle (G1/F13)" rule
  3. Press G1 once to record, press again to transcribe and paste
EOF
