#!/bin/bash
# Mandala Studio — portable launcher (macOS, Python built-in)
cd "$(dirname "$0")"
ROOT="$(pwd)/app"
PORT=3847

if [ ! -f "$ROOT/index.html" ]; then
  echo "ERROR: app/index.html not found."
  read -r -p "Press Enter to exit..."
  exit 1
fi

# Free port if needed
for p in $PORT 3848 3849 3850; do
  if ! lsof -iTCP:$p -sTCP:LISTEN >/dev/null 2>&1; then
    PORT=$p
    break
  fi
done

echo ""
echo "  Mandala Studio"
echo "  http://127.0.0.1:$PORT/"
echo "  Keep this window open. Close it to stop."
echo ""

cd "$ROOT" || exit 1
# Python 3 http server
if command -v python3 >/dev/null 2>&1; then
  (sleep 0.6 && open "http://127.0.0.1:$PORT/") &
  python3 -m http.server "$PORT" --bind 127.0.0.1
elif command -v python >/dev/null 2>&1; then
  (sleep 0.6 && open "http://127.0.0.1:$PORT/") &
  python -m SimpleHTTPServer "$PORT"
else
  echo "Python not found. Install Python 3 or open app/index.html is not supported."
  read -r -p "Press Enter to exit..."
  exit 1
fi
