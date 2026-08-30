#!/usr/bin/env bash
# Замазка: готовит улику к публикации — прячет значения секретов, оставляет хеши.
#
#   ./zamazat.sh syroe.txt > ulika.txt        замазать файл
#   команда | ./zamazat.sh > ulika.txt        замазать поток
#   ./zamazat.sh --proverit ulika.txt         проверить, что публиковать безопасно
#   ./zamazat.sh --proverit .                 проверить всю папку перед push
#
# Что НЕ трогает: 40-значные шестнадцатеричные хеши. Хеш — это и есть улика:
# он доказывает, что объект существует, ничего не разглашая.

set -uo pipefail

MASK='‹ЗАМАЗАНО›'

maskit() {
  sed -E \
    -e "s/sk_(live|test)_[A-Za-z0-9]{4,}/sk_\1_${MASK}/g" \
    -e "s/gh[pousr]_[A-Za-z0-9]{10,}/gh?_${MASK}/g" \
    -e "s/AKIA[0-9A-Z]{8,}/AKIA${MASK}/g" \
    -e "s/xox[baprs]-[A-Za-z0-9-]{8,}/xox?-${MASK}/g" \
    -e "s/(-----BEGIN [A-Z ]*PRIVATE KEY-----).*/\1 ${MASK}/g" \
    -e "s/([Pp]assword|PASSWORD|[Ss]ecret|SECRET|[Aa]pi_?[Kk]ey|API_?KEY|[Tt]oken|TOKEN)([[:space:]]*[=:][[:space:]]*)[\"']?[A-Za-z0-9_\/+.-]{8,}[\"']?/\1\2${MASK}/g"
}

scan() {
  # печатает найденные опасные места; 0 — чисто, 1 — есть что прятать
  local target="$1" found=0 out
  out=$(grep -rInE \
      -e 'sk_(live|test)_[A-Za-z0-9]{4,}' \
      -e 'gh[pousr]_[A-Za-z0-9]{10,}' \
      -e 'AKIA[0-9A-Z]{8,}' \
      -e 'xox[baprs]-[A-Za-z0-9-]{8,}' \
      -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' \
      -e '([Pp]assword|[Ss]ecret|[Aa]pi_?[Kk]ey|[Tt]oken)[[:space:]]*[=:][[:space:]]*[A-Za-z0-9_/+.-]{8,}' \
      --exclude-dir=.git --exclude='zamazat.sh' "$target" 2>/dev/null | grep -v "$MASK") || true
  if [ -n "$out" ]; then found=1; printf '%s\n' "$out"; fi
  return $found
}

if [ "${1:-}" = "--proverit" ]; then
  T="${2:-.}"
  echo "=== ЗАМАЗКА: проверка перед публикацией ==="
  echo "смотрю: $T"
  echo ""
  if scan "$T"; then
    echo "[✓] живых секретов не вижу — публиковать можно"
    exit 0
  else
    echo ""
    echo "[✗] ВЫШЕ — то, что уйдёт в публичный репозиторий как есть."
    echo "    Пропустите файл через замазку и вставьте результат заново:"
    echo "      ./zamazat.sh <файл> > ulika.txt"
    exit 1
  fi
fi

if [ $# -ge 1 ] && [ -f "$1" ]; then
  maskit < "$1"
else
  maskit
fi
