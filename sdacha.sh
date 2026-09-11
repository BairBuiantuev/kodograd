#!/usr/bin/env bash
# Самопроверка Ф0-1 «Летопись и списки».
# Запускать ИЗНУТРИ репозитория git-forensics:  bash sdacha.sh
# Ничего не меняет — только смотрит и печатает отчёт, который вы вставляете в чат.

set -uo pipefail

OK=0; FAIL=0; WARN=0
ok()   { printf '  [✓] %s\n' "$1"; OK=$((OK+1)); }
no()   { printf '  [✗] %s\n' "$1"; FAIL=$((FAIL+1)); }
warn() { printf '  [~] %s\n' "$1"; WARN=$((WARN+1)); }
head_() { printf '\n%s\n' "$1"; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Это не репозиторий git. Запускайте изнутри git-forensics."; exit 1
fi

README=$(ls README.md readme.md 2>/dev/null | head -1)
R=""; [ -n "$README" ] && R=$(cat "$README")

echo "=============================================="
echo " ОТЧЁТ САМОПРОВЕРКИ · Ф0-1 Летопись и списки"
echo " репозиторий: $(basename "$(git rev-parse --show-toplevel)")"
echo " скреп в цепи: $(git rev-list --count --all 2>/dev/null)"
echo "=============================================="

head_ "ЧАСТЬ 0 — объектная модель руками"
if [ -z "$R" ]; then no "README.md не найден — без него сдавать нечего"
else
  for cmd in hash-object write-tree commit-tree update-ref; do
    if printf '%s' "$R" | grep -q -- "$cmd"; then ok "в README есть $cmd"
    else no "в README нет $cmd — таблица «герой → команда» неполная"; fi
  done
  if printf '%s' "$R" | grep -qiE 'мерил|разложник|скрепник|кивун'; then
    ok "герои названы своими именами (связь с сагой видна)"
  else warn "в README нет имён героев — связь с сагой не видна"; fi
fi

head_ "ЧАСТЬ 1-2 — утечка доказана и вычищена"
LEAK_LOG=$(git log -p -S "sk_live" --all 2>/dev/null | head -c 200)
if [ -z "$LEAK_LOG" ]; then ok "секрет sk_live в цепи не находится"
else no "секрет ВСЁ ЕЩЁ в цепи — filter-repo не отработал"; fi

LEAK_OBJ=$(git rev-list --objects --all 2>/dev/null | grep -c '\.env$' || true)
if [ "${LEAK_OBJ:-0}" -eq 0 ]; then ok ".env не встречается среди объектов"
else no ".env всё ещё среди объектов ($LEAK_OBJ шт.)"; fi

UNREACH=$(git fsck --unreachable 2>/dev/null | grep -c '^unreachable' || true)
if [ "${UNREACH:-0}" -eq 0 ]; then ok "подклеть выметена (недостижимых объектов нет)"
else warn "в подклети ещё $UNREACH объектов — прогоните reflog expire + gc --prune=now"; fi

if printf '%s' "$R" | grep -qiE 'смен(ить|ил|а).{0,30}секрет|ротац'; then
  ok "в README есть третий шаг — смена самого секрета"
else no "в README не сказано про СМЕНУ секрета — а это единственный шаг, отменяющий утечку"; fi

if printf '%s' "$R" | grep -qiE 'наслой|прячет.{0,20}не убирает|слой'; then
  ok "связь с законом Наслоя зафиксирована"
else no "нет абзаца про Наслоя — это главный мостик между Ф0-1 и кварталом 1"; fi

head_ "ЧАСТЬ 3 — автоматизация"
HOOK=$(git rev-parse --git-path hooks/pre-commit)
if [ -x "$HOOK" ]; then ok "хук pre-commit на месте и исполняемый"
elif [ -f "$HOOK" ]; then no "хук pre-commit есть, но не исполняемый (chmod +x)"
else no "хука pre-commit нет"; fi

WF=$(ls .github/workflows/*.y*ml 2>/dev/null | head -1)
if [ -n "$WF" ]; then
  ok "конвейер найден: $WF"
  if grep -q 'fetch-depth: *0' "$WF"; then ok "fetch-depth: 0 задан — сканируется вся цепь"
  else no "нет fetch-depth: 0 — сканируется одна скрепа, смысл теряется"; fi
  if grep -qiE 'gitleaks|trufflehog' "$WF"; then ok "в конвейере есть поиск секретов"
  else no "в конвейере нет поиска секретов"; fi
else no "конвейера .github/workflows не найдено"; fi

head_ "ПЕЧАТЬ СМОЛИ — подписи"
SIGNED=$(git log --format='%G?' 2>/dev/null | grep -c '^[GU]' || true)
UNSIGNED=$(git log --format='%G?' 2>/dev/null | grep -c '^N' || true)
if [ "${SIGNED:-0}" -gt 0 ]; then ok "подписанных скреп: $SIGNED"
else no "ни одной подписанной скрепы"; fi
if [ "${UNSIGNED:-0}" -gt 0 ] && [ "${SIGNED:-0}" -gt 0 ]; then
  ok "рядом есть неподписанные ($UNSIGNED) — контраст «ЧТО против КТО» виден"
else warn "нет контраста подписанной и неподписанной скрепы"; fi

head_ "ЖУРНАЛ И ЗАПИСЬ"
if [ -f "ЖУРНАЛ.md" ] || [ -f "JOURNAL.md" ]; then ok "журнал ведётся"
else warn "журнала нет — по нему потом делается пятиминутный рассказ"; fi
if printf '%s' "$R" | grep -qiE 'запис|audio|mp3|m4a|голос'; then ok "упомянута пятиминутная запись"
else warn "нет упоминания пятиминутной записи"; fi

head_ "ЖИВАЯ ПРОВЕРКА ХУКА (безопасно, ничего не коммитит)"
if [ -x "$HOOK" ]; then
  TMPF=".sdacha_probe_$$"
  echo 'token=sk_live_PROBE_0000000000' > "$TMPF"
  git add "$TMPF" 2>/dev/null
  if "$HOOK" >/dev/null 2>&1; then no "хук ПРОПУСТИЛ подложенный секрет"
  else ok "хук задержал подложенный секрет"; fi
  git reset -q "$TMPF" 2>/dev/null; rm -f "$TMPF"
else warn "хук не проверен — его нет"; fi

TOTAL=$((OK+FAIL))
echo ""
echo "=============================================="
printf " ИТОГ: пройдено %s из %s   (замечаний: %s)\n" "$OK" "$TOTAL" "$WARN"
if [ "$FAIL" -eq 0 ]; then
  echo " Готово к сдаче. Скопируйте этот отчёт в чат."
else
  echo " Есть незакрытые пункты — см. [✗] выше."
fi
echo "=============================================="
echo ""
echo "--- вставьте в чат вместе с отчётом ---"
echo "ссылка на репозиторий: <URL или «локально»>"
echo "часов потрачено: <…>"
echo "что удивило: <одна фраза>"
echo "что осталось непонятным: <одна фраза>"
