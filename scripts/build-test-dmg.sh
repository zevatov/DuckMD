#!/usr/bin/env bash
#
# build-test-dmg.sh — локальная тестовая сборка DuckMD (.app → versioned .dmg)
# БЕЗ платного Apple Developer аккаунта, БЕЗ публикации, БЕЗ удалённого репозитория.
#
# Стратегия подписи (в порядке попыток, переопределяется SIGN_MODE=...):
#   auto    — как в project.yml (Release: Manual + «Apple Development» + Team ID).
#             Работает, когда сертификат «Apple Development» доступен xcodebuild'у.
#   unsigned — сборка без подписи (CODE_SIGNING_ALLOWED=NO), затем ручная подпись
#             через codesign CLI тем же сертификатом (обходной путь, подтверждён рабочий).
#   adhoc   — сборка без подписи + ad-hoc подпись ("-"): запуск только на этой машине,
#             без Team ID. Максимально безопасный fallback.
#
# Не делает: notarization, Developer ID, публикацию, git-операции.
#
# Использование:
#   ./scripts/build-test-dmg.sh                # полный прогон: build → sign → versioned DMG
#   DRY_RUN=1 ./scripts/build-test-dmg.sh      # dry-run: показать план команд, ничего не выполнять
#   SIGN_MODE=adhoc ./scripts/build-test-dmg.sh
#   SIGN_MODE=unsigned ./scripts/build-test-dmg.sh
#   SIGN_MODE=auto ./scripts/build-test-dmg.sh
#
# Артефакты (хранятся рядом, versioned):
#   build/dist/DuckMD-<VERSION>.app
#   build/dist/DuckMD-<VERSION>.dmg
#
set -euo pipefail

PROJECT_NAME="DuckMD"
SCHEME="DuckMD"
CONFIGURATION="Release"
VERSION_FILE="build/.version"
DIST_DIR="build/dist"
DERIVED_DIR="build/DerivedData"
BUILD_LOG="build/build-test-dmg.log"

log()  { echo "==> $*"; }
warn() { echo "    WARN: $*" >&2; }
die()  { echo "    FAIL: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# [0/6] Окружение: инструменты, сертификат, режим подписи
# ---------------------------------------------------------------------------
log "[0/6] Окружение и режим подписи"

command -v xcodegen >/dev/null 2>&1 || die "xcodegen не найден (brew install xcodegen)"
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild не найден (установи Xcode)"
command -v hdiutil >/dev/null 2>&1 || die "hdiutil не найден"

SIGN_MODE="${SIGN_MODE:-auto}"
case "${SIGN_MODE}" in
  auto|unsigned|adhoc) ;;
  *) die "SIGN_MODE должен быть auto|unsigned|adhoc (получено: ${SIGN_MODE})" ;;
esac

# Сертификат «Apple Development» (бесплатная локальная подпись).
# Team ID НЕ парсим из имени сертификата (суффикс в скобках — НЕ Team ID),
# читаем реальный TeamIdentifier через codesign.
# sed, а не grep -o c '+': в BSD grep (BRE) '+' — литерал, матч бы не сработал.
APPDEV_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1 || true)"

if [[ -n "${APPDEV_IDENTITY}" ]]; then
  log "    Сертификат «Apple Development» найден: ${APPDEV_IDENTITY}"
else
  warn "Сертификат «Apple Development» не найден в keychain."
  if [[ "${SIGN_MODE}" == "auto" ]]; then
    warn "Откатываю SIGN_MODE auto → adhoc (подпись без Team ID)."
    SIGN_MODE="adhoc"
  fi
fi

# Dry-run фиксируем до изменений файловой системы.
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  log "    DRY_RUN=1 — команды будут показаны, но НЕ выполнены."
fi

run() {
  # run <описание> <команда...> — выполнить или показать в dry-run.
  local desc="$1"; shift
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "    [dry-run] $*"
  else
    echo "    $desc"
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# [1/6] Генерация проекта
# ---------------------------------------------------------------------------
log "[1/6] xcodegen generate"
run "генерация Xcode-проекта" xcodegen generate

# ---------------------------------------------------------------------------
# [2/6] Сборка Release
# ---------------------------------------------------------------------------
log "[2/6] xcodebuild build (${CONFIGURATION})"

BUILD_ARGS=(
  -project "${PROJECT_NAME}.xcodeproj"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination 'platform=macOS'
  -derivedDataPath "${DERIVED_DIR}"
)

case "${SIGN_MODE}" in
  auto)
    # Полная подпись силами xcodebuild (project.yml: Manual + Apple Development + Team).
    BUILD_ARGS+=( build )
    ;;
  unsigned|adhoc)
    # Сборка без подписи; подпись отдельным шагом.
    BUILD_ARGS+=( build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO )
    ;;
esac

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "    [dry-run] xcodebuild ${BUILD_ARGS[*]}"
else
  mkdir -p build
  # Лог полный; на консоль — только warnings/errors/итог.
  if ! xcodebuild "${BUILD_ARGS[@]}" 2>&1 | tee "${BUILD_LOG}" | grep -E "warning:|error:|BUILD (SUCCEEDED|FAILED)"; then
    grep -E "error:" "${BUILD_LOG}" | head -5 || true
    die "xcodebuild завершился с ошибкой (см. ${BUILD_LOG})"
  fi
fi

APP_SRC="${DERIVED_DIR}/Build/Products/${CONFIGURATION}/${PROJECT_NAME}.app"
if [[ "${DRY_RUN:-0}" != "1" ]]; then
  [[ -d "${APP_SRC}" ]] || die "Не найден ${APP_SRC} после сборки"
fi

# ---------------------------------------------------------------------------
# [3/6] Подпись (по режиму)
# ---------------------------------------------------------------------------
log "[3/6] Подпись (SIGN_MODE=${SIGN_MODE})"

case "${SIGN_MODE}" in
  auto)
    log "    Подпись выполнена xcodebuild'ом на шаге 2."
    if [[ "${DRY_RUN:-0}" != "1" ]]; then
      codesign --verify --strict "${APP_SRC}" || die "Подпись невалидна: ${APP_SRC}"
      log "    codesign --verify: OK"
    fi
    ;;
  unsigned)
    if [[ -z "${APPDEV_IDENTITY}" ]]; then
      warn "Сертификат недоступен → ad-hoc подпись вместо unsigned."
    fi
    IDENTITY_TO_USE="${APPDEV_IDENTITY:--}"
    run "codesign (hardened runtime + entitlements)" \
      codesign --force --sign "${IDENTITY_TO_USE}" --options runtime \
        --entitlements security/DuckMD.entitlements "${APP_SRC}"
    run "codesign --verify" codesign --verify --strict "${APP_SRC}"
    ;;
  adhoc)
    run "codesign ad-hoc (-)" \
      codesign --force --sign - --options runtime \
        --entitlements security/DuckMD.entitlements "${APP_SRC}"
    run "codesign --verify" codesign --verify --strict "${APP_SRC}"
    ;;
esac

# ---------------------------------------------------------------------------
# [4/6] Версия из собранного .app (read-back, не из project.yml)
# ---------------------------------------------------------------------------
log "[4/6] Версия из собранного бандла"
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "    [dry-run] VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' ${APP_SRC}/Contents/Info.plist)"
  VERSION="0.0.0-dryrun"
else
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_SRC}/Contents/Info.plist")" \
    || die "Не удалось прочитать CFBundleShortVersionString из ${APP_SRC}"
  [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9]+)?$ ]] \
    || die "Подозрительная версия: '${VERSION}' — проверь MARKETING_VERSION в project.yml"
  printf '%s' "${VERSION}" > "${VERSION_FILE}"
fi
log "    Версия: ${VERSION}"

# ---------------------------------------------------------------------------
# [5/6] Копирование .app в dist с версией в имени
# ---------------------------------------------------------------------------
log "[5/6] Копирование .app → ${DIST_DIR}"
VERSIONED_APP="${DIST_DIR}/${PROJECT_NAME}-${VERSION}.app"
run "создание ${DIST_DIR}" mkdir -p "${DIST_DIR}"
if [[ "${DRY_RUN:-0}" != "1" ]]; then
  rm -rf "${VERSIONED_APP}"   # идемпотентность: перезапись прежней копии той же версии
  # ditto сохраняет симлинки/права — обязательного для .app; cp -R ломает подпись редко, но ditto надёжнее.
  ditto "${APP_SRC}" "${VERSIONED_APP}"
  codesign --verify --strict "${VERSIONED_APP}" || die "Подпись невалидна после копирования: ${VERSIONED_APP}"
  log "    Готово: ${VERSIONED_APP} (подпись проверена после копирования)"
else
  echo "    [dry-run] rm -rf ${VERSIONED_APP} && ditto ${APP_SRC} ${VERSIONED_APP} && codesign --verify --strict ${VERSIONED_APP}"
fi

# ---------------------------------------------------------------------------
# [6/6] Versioned DMG
# ---------------------------------------------------------------------------
log "[6/6] Сборка ${DIST_DIR}/${PROJECT_NAME}-${VERSION}.dmg"
VERSIONED_DMG="${DIST_DIR}/${PROJECT_NAME}-${VERSION}.dmg"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "    [dry-run] rm -f ${VERSIONED_DMG}"
  echo "    [dry-run] mkdir -p ${DIST_DIR}/dmg-staging && ln -s /Applications ${DIST_DIR}/dmg-staging/Applications"
  echo "    [dry-run] ditto ${VERSIONED_APP} ${DIST_DIR}/dmg-staging/${PROJECT_NAME}-${VERSION}.app"
  echo "    [dry-run] hdiutil create -volname '${PROJECT_NAME} ${VERSION}' -srcfolder ${DIST_DIR}/dmg-staging -ov -format UDZO ${VERSIONED_DMG}"
  echo "    [dry-run] hdiutil verify ${VERSIONED_DMG}"
  echo "==> Dry-run завершён. Ничего не собрано."
  exit 0
fi

rm -f "${VERSIONED_DMG}"
STAGING="${DIST_DIR}/dmg-staging"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
ln -s /Applications "${STAGING}/Applications"
ditto "${VERSIONED_APP}" "${STAGING}/${PROJECT_NAME}-${VERSION}.app"

hdiutil create \
  -volname "${PROJECT_NAME} ${VERSION}" \
  -srcfolder "${STAGING}" \
  -ov -format UDZO \
  "${VERSIONED_DMG}" >/dev/null || die "hdiutil create упал"

# Read-back: целостность DMG.
hdiutil verify "${VERSIONED_DMG}" >/dev/null 2>&1 || die "hdiutil verify упал для ${VERSIONED_DMG}"
rm -rf "${STAGING}"

# ---------------------------------------------------------------------------
# Итог
# ---------------------------------------------------------------------------
log "Готово. Артефакты:"
ls -lh "${DIST_DIR}" | grep -v '^total' || true
echo
echo "    Установка: open ${VERSIONED_DMG}  →  перетащить ${PROJECT_NAME}-${VERSION}.app в Applications"
if [[ "${SIGN_MODE}" == "adhoc" ]]; then
  echo
  echo "    ВНИМАНИЕ: ad-hoc подпись — приложение запустится только на этой машине"
  echo "    (первый запуск: правый клик → Открыть, либо xattr -dr com.apple.quarantine ${VERSIONED_APP})."
fi
