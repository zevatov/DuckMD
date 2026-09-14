#!/usr/bin/env bash
#
# build-release.sh — release-сборка DuckMD для прямой раздачи (Developer ID, без MAS).
#
# Пайплайн: xcodegen generate → xcodebuild archive → codesign --verify →
#           инструктивные echo-строки notarization (выполняются вручную).
#
# Требования:
#   - Сертификат «Developer ID Application» в keychain (проверяется на шаге 0).
#   - DEVELOPMENT_TEAM, вписанный в project.yml (settings.base и/или configs.Release).
#
# Использование:
#   ./scripts/build-release.sh            # полный прогон (archive + verify + export)
#   DRY_RUN=1 ./scripts/build-release.sh  # dry-run: показать команды, ничего не выполнять
#
set -euo pipefail

PROJECT_NAME="DuckMD"
SCHEME="DuckMD"
CONFIGURATION="Release"
ARCHIVE_PATH="build/${PROJECT_NAME}.xcarchive"
EXPORT_DIR="build/export"
EXPORT_OPTIONS_PLIST="build/ExportOptions.plist"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/${PROJECT_NAME}.app"

echo "==> [0/5] Проверка сертификата «Developer ID Application»"
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "    OK: сертификат найден:"
  security find-identity -v -p codesigning | grep "Developer ID Application"
elif [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "    WARN (dry-run): сертификата нет, полный прогон упадёт на этом шаге."
else
  echo "    FAIL: сертификат «Developer ID Application» не найден в keychain."
  echo "    Получи его на https://developer.apple.com/account (Certificates, Identifiers & Profiles),"
  echo "    затем впиши DEVELOPMENT_TEAM в project.yml и повтори."
  exit 1
fi

echo "==> [1/5] xcodegen generate"
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "    [dry-run] xcodegen generate"
else
  xcodegen generate
fi

echo "==> [2/5] xcodebuild archive (${CONFIGURATION}, hardened runtime)"
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "    [dry-run] xcodebuild -project ${PROJECT_NAME}.xcodeproj -scheme ${SCHEME} -configuration ${CONFIGURATION} -archivePath ${ARCHIVE_PATH} archive"
else
  xcodebuild -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    archive
fi

echo "==> [3/5] Проверка подписи (codesign + Gatekeeper)"
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "    [dry-run] codesign --verify --deep --strict ${APP_PATH}"
  echo "    [dry-run] spctl -a -vv -t execute ${APP_PATH}"
else
  codesign --verify --deep --strict "${APP_PATH}"
  echo "    Подпись валидна. Проверка Gatekeeper:"
  spctl -a -vv -t execute "${APP_PATH}"
fi

echo "==> [4/5] Экспорт .app из архива (для ручной раздачи)"
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "    [dry-run] запись ${EXPORT_OPTIONS_PLIST} (method=developer-id, signingStyle=automatic)"
  echo "    [dry-run] xcodebuild -exportArchive -archivePath ${ARCHIVE_PATH} -exportPath ${EXPORT_DIR} -exportOptionsPlist ${EXPORT_OPTIONS_PLIST}"
else
  mkdir -p "${EXPORT_DIR}"
  cat > "${EXPORT_OPTIONS_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
EOF
  xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}"
  echo "    Готово: ${EXPORT_DIR}/${PROJECT_NAME}.app"
fi

echo "==> [5/5] Notarization — ВРУЧНУЮ, команды ниже скриптом НЕ выполняются:"
echo
echo "    # 1. Однократно: сохранить креды в keychain-профиль (плейсхолдер KEYCHAIN_PROFILE):"
echo "    xcrun notarytool store-credentials KEYCHAIN_PROFILE \\"
echo "      --apple-id \"your@email\" --team-id \"TEAMID\" --password \"app-specific-password\""
echo
echo "    # 2. Отправить .app (в zip) на нотаризацию и дождаться статуса:"
echo "    ditto -c -k --keepParent ${EXPORT_DIR}/${PROJECT_NAME}.app ${EXPORT_DIR}/${PROJECT_NAME}.zip"
echo "    xcrun notarytool submit ${EXPORT_DIR}/${PROJECT_NAME}.zip --keychain-profile KEYCHAIN_PROFILE --wait"
echo
echo "    # 3. Прикрепить билет (staple) и проверить:"
echo "    xcrun stapler staple ${EXPORT_DIR}/${PROJECT_NAME}.app"
echo "    xcrun stapler validate ${EXPORT_DIR}/${PROJECT_NAME}.app"
echo
echo "==> Скрипт завершён."
