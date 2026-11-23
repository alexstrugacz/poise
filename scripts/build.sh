#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR%/scripts}"
APP_DIR="${PROJECT_DIR}/dist/Poise.app"
INSTALL_DIR="${POISE_INSTALL_DIR:-${HOME}/Applications}"
INSTALL_APP="${INSTALL_DIR}/Poise.app"

if [[ "${1:-}" != "" && "${1:-}" != "--install" ]]; then
    echo "Usage: scripts/build.sh [--install]" >&2
    exit 1
fi

cd "${PROJECT_DIR}"
# Avoid a nested sandbox for this local package's manifest in managed workspaces.
xcrun swift build --disable-sandbox --configuration release -debug-info-format none --scratch-path .build --cache-path .build/cache
BIN_DIR="$(xcrun swift build --disable-sandbox --configuration release -debug-info-format none --scratch-path .build --cache-path .build/cache --show-bin-path)"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/Poise" "${APP_DIR}/Contents/MacOS/Poise"
cp "${PROJECT_DIR}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
xcrun swift "${SCRIPT_DIR}/MakeIcon.swift" "${PROJECT_DIR}/.build/Poise.iconset" "${APP_DIR}/Contents/Resources/Poise.icns"
codesign --force --sign - --identifier local.alexstrugacz.poise "${APP_DIR}"
codesign --verify --strict "${APP_DIR}"
echo "Built: ${APP_DIR}"

if [[ "${1:-}" == "--install" ]]; then
    if [[ -e "${INSTALL_APP}" ]]; then
        EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INSTALL_APP}/Contents/Info.plist" 2>/dev/null || true)"
        if [[ "${EXISTING_ID}" != "local.alexstrugacz.poise" ]]; then
            echo "An unrelated app already exists at ${INSTALL_APP}; leaving it in place." >&2
            exit 1
        fi
    fi
    mkdir -p "${INSTALL_DIR}"
    ditto "${APP_DIR}" "${INSTALL_APP}"
    echo "Installed: ${INSTALL_APP}"
fi
