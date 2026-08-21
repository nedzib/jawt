#!/bin/sh
# Muestra una notificación de macOS vía osascript.
# Los argumentos se pasan de forma posicional para evitar problemas
# con comillas en el texto.
TITLE="${JAWT_INPUT_TITLE:-JAWT}"
MESSAGE="${JAWT_INPUT_MESSAGE:-}"

osascript \
  -e 'on run argv' \
  -e 'display notification (item 2 of argv) with title (item 1 of argv)' \
  -e 'end run' \
  "$TITLE" "$MESSAGE" >/dev/null 2>&1

echo '{"result":"ok"}'
