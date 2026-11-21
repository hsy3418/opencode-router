#!/usr/bin/env bash
# Remove the files install.sh manages. Your notes folder and your own files are left alone.
set -euo pipefail
: "${HOME:?HOME is not set — refusing to guess where to install}"

MARKER="# Managed by opencode-router."
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

for f in agents/router.md agents/explorer.md agents/deep-thinker.md commands/wrapup.md commands/continue.md; do
  path="$CONFIG_DIR/$f"
  if [ -f "$path" ] && grep -qF "$MARKER" "$path"; then
    rm "$path"; echo "removed  $path"
  elif [ -f "$path" ]; then
    echo "skipped  $path (not written by install.sh)"
  fi
done

agents_md="$CONFIG_DIR/AGENTS.md"
if [ -f "$agents_md" ] && grep -q 'opencode-router:start' "$agents_md"; then
  tmp="$(mktemp)"
  awk '
    /<!-- opencode-router:start -->/ { skip = 1; next }
    /<!-- opencode-router:end -->/   { skip = 0; next }
    !skip { lines[++n] = $0; if ($0 ~ /[^[:space:]]/) last = n }
    END { for (i = 1; i <= last; i++) print lines[i] }
  ' "$agents_md" > "$tmp"
  cat "$tmp" > "$agents_md"; rm -f "$tmp"
  echo "removed  notes block from $agents_md"
  if [ ! -s "$agents_md" ]; then rm "$agents_md"; echo "removed  $agents_md (it was empty)"; fi
fi

rm -f "$CONFIG_DIR/.opencode-router-preset"
echo
echo "Your notes folder was not touched. If you set \"default_agent\": \"router\" in opencode.json, remove that line too."
