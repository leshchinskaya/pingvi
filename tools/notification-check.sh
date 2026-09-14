#!/bin/bash
# Human-in-the-loop check: API success does not establish the rendered icon.
set -euo pipefail
if [[ "${1:-}" == "--record" ]]; then
    result="${2:?Use missing or visible, based on the actual banner}"
else
    open "$HOME/Applications/Pingvi.app" --args --test-notification
    read -r -p 'Новый баннер: пингвин виден? (visible/missing): ' result
fi
printf 'NOTIFICATION_ICON=%s\n' "$result"
[[ "$result" == "visible" ]]
