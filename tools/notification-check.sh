#!/bin/bash
# Human-in-the-loop check: API success does not establish the rendered icon.
set -euo pipefail
if [[ "${1:-}" == "--record" ]]; then
    result="${2:?Use missing or visible, based on the actual banner}"
else
    app="${PINGVI_APP:-/Applications/Pingvi.app}"
    if [[ ! -d "$app" && -d "$HOME/Applications/Pingvi.app" ]]; then app="$HOME/Applications/Pingvi.app"; fi
    [[ -d "$app" ]] || { echo 'Set PINGVI_APP to the installed Pingvi.app path.' >&2; exit 2; }
    open "$app"
    # Launch arguments are ignored when the app is already running. Use the same UI path in both cases.
    printf '%s\n' 'В Pingvi: Настройки → Уведомления → Тестовое уведомление. Проверьте статус и новый баннер.'
    read -r -p 'Новый баннер: пингвин виден? (visible/missing): ' result
fi
printf 'NOTIFICATION_ICON=%s\n' "$result"
[[ "$result" == "visible" ]]
