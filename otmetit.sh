#!/usr/bin/env bash
# Отметить выполненное задание: улика + галочка + подписанная скрепа.
#
#   ./otmetit.sh 0.1 "Мерило: заклеймил лист, доказал содержимую адресацию"
#
# Лучше — с уликой на входе (тогда в репозиторий ляжет настоящий вывод):
#
#   git hash-object -w gramota.txt | ./otmetit.sh 0.1 "Мерило: заклеймил лист"
#   { git cat-file -p 4b2a1f; } | ./otmetit.sh 0.2 "Разложник: составил список"
#
# Что делает: кладёт улику в evidence/<id>.md, ставит [x] в README,
# сшивает скрепу с внятной запиской. Ничего не пушит — push вручную.

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Как звать:  ./otmetit.sh <номер> \"<что сделано>\""
  echo "Например:   ./otmetit.sh 0.1 \"Мерило: заклеймил лист\""
  exit 1
fi

ID="$1"; shift
DESC="$*"

git rev-parse --git-dir >/dev/null 2>&1 || { echo "Это не репозиторий git."; exit 1; }

mkdir -p evidence
EV="evidence/${ID}.md"

{
  printf '# %s — %s\n\n' "$ID" "$DESC"
  printf '_отмечено: %s_\n\n' "$(date '+%Y-%m-%d %H:%M')"
  printf '```\n'
  if [ -t 0 ]; then
    printf '(вывод не передан — задание отмечено без улики)\n'
  else
    cat
  fi
  printf '```\n'
} > "$EV"

# галочка: правим и README рядом, и README в корне репозитория
ROOT=$(git rev-parse --show-toplevel)
ESC=$(printf '%s' "$ID" | sed 's/[.[\*^$]/\\&/g')
TICKED=0
SEEN=""
for RM in "$PWD/README.md" "$ROOT/README.md"; do
  [ -f "$RM" ] || continue
  case " $SEEN " in *" $RM "*) continue;; esac
  SEEN="${SEEN:-} $RM"
  if grep -qE "^- \[ \] ${ESC}([^A-Za-zА-Яа-я0-9]|\$)" "$RM"; then
    sed -i -E "s/^- \[ \] (${ESC}([^A-Za-zА-Яа-я0-9]|\$).*)/- [x] \1/" "$RM"
    git add "$RM"; TICKED=1
  fi
done
if [ "$TICKED" = "0" ]; then
  echo "  ~ галочку для «$ID» в README не нашёл — проверьте номер"
fi

git add "$EV"
if [ -f "$ROOT/ЖУРНАЛ.md" ]; then git add "$ROOT/ЖУРНАЛ.md" || true; fi

if git diff --cached --quiet; then
  echo "Нечего фиксировать — ничего не изменилось."
  exit 0
fi

git commit -q -m "${ID} · ${DESC}"

SIG=$(git log -1 --format='%G?' 2>/dev/null || echo '?')
HASH=$(git log -1 --format='%h')

echo "✓ отмечено: ${ID} — ${DESC}"
echo "  скрепа ${HASH} · улика ${EV}"
case "$SIG" in
  G) echo "  печать Смоли: проверена" ;;
  U|E) echo "  печать есть, но не проверяется — нужен gpg.ssh.allowedSignersFile" ;;
  N) echo "  ~ скрепа без печати. Включить: git config commit.gpgsign true" ;;
  *) echo "  ~ статус подписи неизвестен" ;;
esac
