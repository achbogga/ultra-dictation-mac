#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="UltraDictationInstaller"
APP_DIR="${ROOT_DIR}/dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

xcrun swiftc "${ROOT_DIR}/app/main.swift" -o "${MACOS_DIR}/${APP_NAME}"
cp "${ROOT_DIR}/app/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "${ROOT_DIR}/install.sh" "${RESOURCES_DIR}/install.sh"
cp "${ROOT_DIR}/uninstall.sh" "${RESOURCES_DIR}/uninstall.sh"
cp "${ROOT_DIR}/requirements.txt" "${RESOURCES_DIR}/requirements.txt"
cp -R "${ROOT_DIR}/templates" "${RESOURCES_DIR}/templates"
find "${RESOURCES_DIR}/templates" -name '__pycache__' -type d -prune -exec rm -rf {} +
cp "${ROOT_DIR}/README.md" "${RESOURCES_DIR}/README.md"
chmod +x "${MACOS_DIR}/${APP_NAME}" "${RESOURCES_DIR}/install.sh" "${RESOURCES_DIR}/uninstall.sh"

echo "Built ${APP_DIR}"
