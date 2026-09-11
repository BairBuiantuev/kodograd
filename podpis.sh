#!/usr/bin/env bash
# Печать Смоли: диагностика ssh-подписи коммитов.
#   bash podpis.sh          — только проверить и объяснить
#   bash podpis.sh --fix    — проверить и починить настройки
# Запускать изнутри репозитория.

set -uo pipefail
FIX=0; [ "${1:-}" = "--fix" ] && FIX=1

say()  { printf '  %s\n' "$1"; }
ok()   { printf '  [✓] %s\n' "$1"; }
bad()  { printf '  [✗] %s\n' "$1"; }

echo "=== ПЕЧАТЬ СМОЛИ: проверка ssh-подписи ==="

git rev-parse --git-dir >/dev/null 2>&1 || { echo "Не репозиторий git."; exit 1; }

FMT=$(git config --get gpg.format || echo "")
KEY=$(git config --get user.signingkey || echo "")
SIGN=$(git config --get commit.gpgsign || echo "")
ALLOW=$(git config --get gpg.ssh.allowedSignersFile || echo "")
EMAIL=$(git config --get user.email || echo "")

echo ""
echo "Что сейчас настроено:"
say "gpg.format ................ ${FMT:-(не задан)}"
say "user.signingkey ........... ${KEY:-(не задан)}"
say "commit.gpgsign ............ ${SIGN:-(не задан)}"
say "gpg.ssh.allowedSignersFile  ${ALLOW:-(не задан)}"
say "user.email ................ ${EMAIL:-(не задан)}"

echo ""
echo "Проверки:"
[ "$FMT" = "ssh" ] && ok "формат подписи — ssh" || bad "gpg.format не ssh"
[ "$SIGN" = "true" ] && ok "подписывать включено" || bad "commit.gpgsign не true"

# --- ключ подписи ---
KEYPATH="${KEY/#\~/$HOME}"
KEYOK=0
if [ -z "$KEY" ]; then
  bad "user.signingkey не задан"
elif [ -f "$KEYPATH" ]; then
  ok "файл ключа существует: $KEYPATH"; KEYOK=1
else
  bad "файла ключа НЕТ: $KEYPATH  ← вот это чаще всего и ломает"
fi

# что вообще есть в ~/.ssh
echo ""
echo "Публичные ключи, которые у вас есть:"
FOUND=""
for k in "$HOME"/.ssh/*.pub; do
  [ -e "$k" ] || continue
  say "$k"
  FOUND="${FOUND:-$k}"
done
[ -z "${FOUND:-}" ] && say "(ни одного .pub не найдено)"

# --- список доверенных подписантов ---
echo ""
ALLOWPATH="${ALLOW/#\~/$HOME}"
ALLOWOK=0
if [ -z "$ALLOW" ]; then
  bad "allowedSignersFile не задан — подпись будет ставиться, но НЕ проверяться (%G? = U)"
elif [ ! -f "$ALLOWPATH" ]; then
  bad "файла доверенных подписантов НЕТ: $ALLOWPATH"
elif [ ! -s "$ALLOWPATH" ]; then
  bad "файл доверенных подписантов ПУСТ: $ALLOWPATH"
else
  LINE=$(head -1 "$ALLOWPATH")
  NF=$(printf '%s' "$LINE" | awk '{print NF}')
  if [ "$NF" -lt 3 ]; then
    bad "строка испорчена (полей: $NF, нужно минимум 3): «$LINE»"
    say "    так бывает, когда cat подставил пустоту вместо ключа"
  else
    P1=$(printf '%s' "$LINE" | awk '{print $1}')
    ok "формат строки верный: принципал + тип + ключ"
    if [ "$P1" = "$EMAIL" ]; then ok "принципал совпадает с user.email"; ALLOWOK=1
    else bad "принципал «$P1» ≠ user.email «$EMAIL» — проверка не сойдётся"; fi
    if [ "$KEYOK" = "1" ]; then
      K2=$(awk '{print $1" "$2}' "$KEYPATH")
      A2=$(printf '%s' "$LINE" | awk '{print $2" "$3}')
      [ "$K2" = "$A2" ] && ok "ключ в списке совпадает с ключом подписи" \
                        || bad "ключ в списке НЕ тот, которым подписываете"
    fi
  fi
fi

# --- фактическое состояние скреп ---
echo ""
echo "Последние скрепы (%G?: G=проверена, U=подписана но не доверена, N=без подписи):"
git log --format='  %h %G? %s' -5 2>/dev/null || say "(истории нет)"

# --- починка ---
echo ""
if [ "$FIX" = "1" ]; then
  TARGET="$KEYPATH"
  if [ "$KEYOK" != "1" ]; then
    if [ -n "${FOUND:-}" ]; then TARGET="$FOUND"; else echo "Чинить нечем: нет ни одного .pub"; exit 1; fi
    git config user.signingkey "$TARGET"
    say "поставил user.signingkey = $TARGET"
  fi
  git config gpg.format ssh
  git config commit.gpgsign true
  AF="$HOME/.git-allowed-signers"
  printf '%s %s\n' "$EMAIL" "$(awk '{print $1" "$2}' "$TARGET")" > "$AF"
  git config gpg.ssh.allowedSignersFile "$AF"
  say "переписал $AF под ключ $TARGET"
  echo ""
  echo "Готово. Проверьте на пустой скрепе:"
  echo "  git commit --allow-empty -m 'проверка печати' && git log -1 --format='%h %G?'"
else
  echo "Чтобы починить автоматически:  bash podpis.sh --fix"
fi

echo ""
echo "ВАЖНО, чего не чинит ни один скрипт:"
echo "  на GitHub ключ надо добавить ОТДЕЛЬНО как Signing Key"
echo "  (Settings → SSH and GPG keys → New SSH key → Key type: Signing Key)."
echo "  Ключ, добавленный как Authentication, для подписи НЕ засчитывается —"
echo "  локально будет G, а на GitHub всё равно Unverified."
