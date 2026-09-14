#!/bin/zsh
# G-DIAG: экспорт диагностических логов DuckMD (Unified Logging) за период.
#
# Использование:
#   ./scripts/export-diagnostics.sh [--public|--private] [START_DATETIME [END_DATETIME]]
#   ./scripts/export-diagnostics.sh                       # последние 7 дней, public
#   ./scripts/export-diagnostics.sh --private             # последние 7 дней, private (sudo)
#   ./scripts/export-diagnostics.sh 2026-09-01            # с указанной даты (00:00) по сейчас
#   ./scripts/export-diagnostics.sh "2026-09-01 09:00:00" "2026-09-05 18:00:00"
#
# Результат: duckmd-diagnostics-<timestamp>.log в текущем каталоге
# (паттерн в .gitignore — не коммитится).
#
# Privacy-режимы (явные):
#   public  (по умолчанию) — .private-значения замаскированы как <private>.
#   private                — раскрыть .private-значения: на текущих macOS у
#                            'log show' нет флага --private, раскрытие даёт
#                            запуск от root, поэтому используется sudo.
#
# Что экспортируется: только сообщения приложения DuckMD
# (subsystem net.duckmd.DuckMD). Файл нельзя отправлять целиком без
# просмотра, особенно в режиме private. Содержимое документов не логируется.

set -euo pipefail

SUBSYSTEM="net.duckmd.DuckMD"
OUT="duckmd-diagnostics-$(date +%Y%m%d-%H%M%S).log"

# Privacy-режим по умолчанию — public (безопасный: маскировка <private>).
PRIVACY_MODE="public"
LOG_CMD=(/usr/bin/log show)

START=""
END=""

# Первый аргумент может задавать privacy-режим.
case "${1:-}" in
  --public)
    PRIVACY_MODE="public"
    shift
    ;;
  --private)
    PRIVACY_MODE="private"
    LOG_CMD=(sudo /usr/bin/log show)
    shift
    ;;
esac

case $# in
  0)
    START="$(date -v-7d '+%Y-%m-%d %H:%M:%S')"
    END="$(date '+%Y-%m-%d %H:%M:%S')"
    ;;
  1)
    START="$1 00:00:00"
    END="$(date '+%Y-%m-%d %H:%M:%S')"
    ;;
  2)
    START="$1"
    END="$2"
    ;;
  *)
    echo "Использование: $0 [--public|--private] [START_DATETIME [END_DATETIME]]" >&2
    exit 1
    ;;
esac

echo "Экспорт логов DuckMD (subsystem=$SUBSYSTEM)"
echo "Период: '$START' — '$END'"
echo "Файл:   $OUT"
if [ "$PRIVACY_MODE" = "private" ]; then
  echo "Privacy-режим: PRIVATE — экспорт через sudo, .private-значения будут РАСКРЫТЫ в файле."
else
  echo "Privacy-режим: PUBLIC — .private-значения замаскированы как <private>."
fi
echo

# --info: включить info-уровень. --last не используем, т.к. задаём точный
# интервал через --start/--end. stderr НЕ глотаем: ошибки 'log show'
# видны пользователю.
rc=0
"${LOG_CMD[@]}" \
  --style compact \
  --info \
  --start "$START" \
  --end "$END" \
  --predicate "subsystem == '$SUBSYSTEM'" \
  > "$OUT" || rc=$?

if [ "$rc" -ne 0 ]; then
  echo "ОШИБКА: 'log show' завершился с кодом $rc — экспорт не выполнен (причина выше)." >&2
  rm -f "$OUT"
  exit "$rc"
fi

LINES=$(wc -l < "$OUT" | tr -d ' ')
SIZE=$(du -h "$OUT" | cut -f1)

if [ "$LINES" -eq 0 ]; then
  echo "ВНИМАНИЕ: сообщений subsystem=$SUBSYSTEM за период не найдено, файл пуст: $OUT"
  exit 0
fi

echo "Готово: $OUT ($LINES строк, $SIZE)"
echo
if [ "$PRIVACY_MODE" = "private" ]; then
  echo "Файл может содержать пути ваших файлов (.private раскрыты режимом --private/sudo)."
  echo "Перед передачей обязательно просмотрите файл."
else
  echo "Файл в режиме public: приватные значения замаскированы (<private>)."
  echo "Раскрыть их локально: перезапустите с флагом --private (потребует sudo)."
fi
