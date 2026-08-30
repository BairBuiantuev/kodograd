#!/usr/bin/env bash
# Отметить выполненное задание: улика + галочка + подписанная скрепа.
#
#   ./otmetit.sh 0.1 "Мерило: заклеймил лист, доказал содержимую адресацию"
#
# Улику подают на вход. Два вида входа:
#   1) сырой вывод команд — обернётся в блок кода автоматически
#        git hash-object -w gramota.txt | ./otmetit.sh 0.1 "Мерило: заклеймил лист"
#   2) готовый разбор в markdown (первая строка начинается с #) — ляжет как есть
#        ./otmetit.sh 1.0 "Утечка доказана" < /tmp/1.0-gotovo.md
#
# Что делает: кладёт улику в evidence/<id>.md, ставит [x] в README,
# сшивает скрепу с внятной запиской.
#
# ПУШ НЕ ДЕЛАЕТ. В конце честно говорит, что ещё не ушло к Двойнику,
# и какой командой это исправить. Отправляете вы сами, руками.

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

# читаем то, что подали на вход
IN=""
if [ ! -t 0 ]; then IN=$(cat); fi

if [ -z "$IN" ]; then
  {
    printf '# %s — %s\n\n' "$ID" "$DESC"
    printf '_отмечено: %s_\n\n' "$(date '+%Y-%m-%d %H:%M')"
    printf '```\n(вывод не передан — задание отмечено без улики)\n```\n'
  } > "$EV"
  echo "  ~ улика пустая: задание отмечено без доказательства"
elif printf '%s\n' "$IN" | head -1 | grep -qE '^#'; then
  # готовый разбор — кладём как есть, ничего не оборачиваем
  printf '%s\n' "$IN" > "$EV"
  echo "  улика: готовый разбор принят как есть"
else
  # сырой вывод команд — оборачиваем
  {
    printf '# %s — %s\n\n' "$ID" "$DESC"
    printf '_отмечено: %s_\n\n' "$(date '+%Y-%m-%d %H:%M')"
    printf '```\n%s\n```\n' "$IN"
  } > "$EV"
fi

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
else
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
fi

# ------------------------------------------------------------------
# Где работа: у вас или у Двойника. Скрипт НЕ пушит — только говорит правду.
# ------------------------------------------------------------------
echo ""
echo "--- палата и Двойник ---"

UP=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
if [ -z "${UP:-}" ]; then
  BR=$(git rev-parse --abbrev-ref HEAD)
  if git remote get-url origin >/dev/null 2>&1; then
    echo "  ~ ветка «$BR» ни за кем не следит — push уйдёт в никуда"
    echo "    привязать:  git push -u origin $BR"
  else
    echo "  ~ удалённой палаты нет (origin не задан) — работа только у вас"
  fi
else
  git fetch -q origin 2>/dev/null || echo "  ~ до Двойника не достучался — счёт по последним известным данным"
  COUNTS=$(git rev-list --left-right --count "${UP}...HEAD" 2>/dev/null || echo "? ?")
  BEHIND=$(printf '%s' "$COUNTS" | awk '{print $1}')
  AHEAD=$(printf '%s' "$COUNTS" | awk '{print $2}')
  if [ "$BEHIND" = "?" ]; then
    echo "  ~ сравнить не удалось"
  elif [ "$AHEAD" = "0" ] && [ "$BEHIND" = "0" ]; then
    echo "  ✓ всё отправлено — у вас и у Двойника одна цепь"
  elif [ "$BEHIND" = "0" ]; then
    echo "  ! НЕ ОТПРАВЛЕНО скреп: $AHEAD — на GitHub этой работы ещё нет"
    echo "    отправить:  git push"
    git log --oneline "${UP}..HEAD" | sed 's/^/      /'
  elif [ "$AHEAD" = "0" ]; then
    echo "  ! вы отстали от Двойника на $BEHIND — подтяните: git pull --no-rebase"
  else
    echo "  ✗ ЦЕПИ РАЗОШЛИСЬ: у вас своих $AHEAD, у Двойника своих $BEHIND"
    echo "    push будет отбит (non-fast-forward). Порядок:"
    echo "      git pull --no-rebase     # свести обе цепи, разрешить конфликты"
    echo "      git push"
    echo "    push --force НЕ делать: сотрёт работу, лежащую у Двойника."
  fi
fi
