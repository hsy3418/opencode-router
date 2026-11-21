#!/usr/bin/env bash
# Install the opencode router setup, or switch to another preset.
# Safe to run again: it rewrites only the files it manages and backs up anything else it would replace.
set -euo pipefail
: "${HOME:?HOME is not set — refusing to guess where to install}"

MARKER="# Managed by opencode-router."

usage() {
  cat <<'EOF'
Usage: ./install.sh <preset> [--dry-run]

  <preset>    a file in presets/ without ".env": both, portkey-only, copilot-only
  --dry-run   check the preset and show what would be written; change nothing

Optional environment variables:
  OPENCODE_CONFIG_DIR   where opencode's global config lives (default: ~/.config/opencode)
  NOTES_DIR             your personal notes folder        (default: ~/agent-notes)
EOF
}

PRESET=""
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
    *)
      if [ -n "$PRESET" ]; then echo "Give only one preset." >&2; exit 1; fi
      PRESET="$arg" ;;
  esac
done
if [ -z "$PRESET" ]; then usage >&2; exit 1; fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$REPO_DIR/templates"
PRESET_FILE="$REPO_DIR/presets/$PRESET.env"
if [ ! -f "$PRESET_FILE" ]; then
  echo "No preset named '$PRESET'. Available:" >&2
  for p in "$REPO_DIR"/presets/*.env; do echo "  $(basename "$p" .env)" >&2; done
  exit 1
fi

CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
NOTES_DIR="${NOTES_DIR:-$HOME/agent-notes}"
case "$NOTES_DIR" in "~"*) NOTES_DIR="$HOME${NOTES_DIR#\~}" ;; esac
NOTES_DIR="${NOTES_DIR%/}"
STAMP="$(date +%Y%m%d-%H%M%S)"

# --- Load and check the preset ------------------------------------------------
# shellcheck disable=SC1090
. "$PRESET_FILE"

problems=0
for var in ROUTER_MODEL FAST_MODEL HEAVY_MODEL EXPLORER_STEPS HEAVY_STEPS; do
  val="${!var:-}"
  if [ -z "$val" ]; then
    echo "Preset problem: $var is empty in presets/$PRESET.env" >&2; problems=1; continue
  fi
  case "$val" in
    *TODO*) echo "Preset problem: $var still has a TODO: $val" >&2; problems=1 ;;
  esac
done
for var in ROUTER_MODEL FAST_MODEL HEAVY_MODEL; do
  case "${!var:-}" in
    */*) ;;
    *) echo "Preset problem: $var should look like <provider-id>/<model-id>" >&2; problems=1 ;;
  esac
done
for var in EXPLORER_STEPS HEAVY_STEPS; do
  case "${!var:-}" in
    ''|*[!0-9]*|0) echo "Preset problem: $var should be a whole number above 0" >&2; problems=1 ;;
  esac
done
if [ "$problems" -ne 0 ]; then
  echo "Fix presets/$PRESET.env, then run again. Tip: 'opencode models' lists the model IDs you can use." >&2
  exit 1
fi

# --- Helpers ------------------------------------------------------------------
sed_escape() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

render() {
  sed -e "s|{{ROUTER_MODEL}}|$(sed_escape "$ROUTER_MODEL")|g" \
      -e "s|{{FAST_MODEL}}|$(sed_escape "$FAST_MODEL")|g" \
      -e "s|{{HEAVY_MODEL}}|$(sed_escape "$HEAVY_MODEL")|g" \
      -e "s|{{EXPLORER_STEPS}}|$(sed_escape "$EXPLORER_STEPS")|g" \
      -e "s|{{HEAVY_STEPS}}|$(sed_escape "$HEAVY_STEPS")|g" \
      -e "s|{{NOTES_DIR}}|$(sed_escape "$NOTES_DIR")|g" \
      "$1"
}

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
TMP_COUNT=0

install_rendered() {
  local tpl="$1" dest="$2" tmp
  TMP_COUNT=$((TMP_COUNT + 1)); tmp="$WORK_DIR/$TMP_COUNT"
  render "$tpl" > "$tmp"
  if grep -q '{{' "$tmp"; then
    echo "Internal problem: unfilled placeholder in $tpl" >&2; exit 1
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  would write  $dest"; return
  fi
  mkdir -p "$(dirname "$dest")"
  if [ -f "$dest" ] && ! grep -qF "$MARKER" "$dest"; then
    cp "$dest" "$dest.bak.$STAMP"
    echo "  backed up    $dest -> $(basename "$dest").bak.$STAMP (it was not ours)"
  fi
  cp "$tmp" "$dest"
  echo "  wrote        $dest"
}

update_agents_md() {
  local file="$CONFIG_DIR/AGENTS.md" tmp block
  block="$(render "$TEMPLATES/AGENTS.snippet.md")"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  would add the notes block to  $file"; return
  fi
  mkdir -p "$CONFIG_DIR"
  tmp="$WORK_DIR/agents-md"; : > "$tmp"
  if [ -f "$file" ]; then
    # Drop any earlier copy of our block, and trailing blank lines.
    awk '
      /<!-- opencode-router:start -->/ { skip = 1; next }
      /<!-- opencode-router:end -->/   { skip = 0; next }
      !skip { lines[++n] = $0; if ($0 ~ /[^[:space:]]/) last = n }
      END { for (i = 1; i <= last; i++) print lines[i] }
    ' "$file" > "$tmp"
  fi
  {
    if [ -s "$tmp" ]; then cat "$tmp"; echo; fi
    printf '%s\n' "$block"
  } > "$file"
  echo "  updated      $file (notes block)"
}

setup_notes() {
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -d "$NOTES_DIR" ]; then echo "  notes folder exists, would only add missing files: $NOTES_DIR"
    else echo "  would create notes folder  $NOTES_DIR"; fi
    return
  fi
  local created=0
  if [ ! -d "$NOTES_DIR" ]; then mkdir -p "$NOTES_DIR"; created=1; fi
  mkdir -p "$NOTES_DIR/evidence"
  for f in index.md lessons-inbox.md redo-log.md .gitignore; do
    if [ ! -e "$NOTES_DIR/$f" ]; then cp "$TEMPLATES/notes/$f" "$NOTES_DIR/$f"; fi
  done
  if [ "$created" -eq 1 ]; then
    echo "  created      $NOTES_DIR"
    if command -v git >/dev/null 2>&1; then
      ( cd "$NOTES_DIR" && git init -q && git add -A \
        && git -c user.name="agent-notes" -c user.email="agent-notes@localhost" commit -q -m "Start notes" ) \
        && echo "  git history  started in $NOTES_DIR (local only, no remote)"
    fi
  else
    echo "  notes folder exists, added only missing files: $NOTES_DIR"
  fi
}

# --- Do it --------------------------------------------------------------------
echo "Preset:        $PRESET"
echo "  main agent   $ROUTER_MODEL"
echo "  explorer     $FAST_MODEL  (steps: $EXPLORER_STEPS)"
echo "  deep-thinker $HEAVY_MODEL  (steps: $HEAVY_STEPS)"
echo "Config folder: $CONFIG_DIR"
echo "Notes folder:  $NOTES_DIR"
[ "$DRY_RUN" -eq 1 ] && echo "(dry run — nothing will change)"
echo

for name in router explorer deep-thinker; do
  install_rendered "$TEMPLATES/agents/$name.md" "$CONFIG_DIR/agents/$name.md"
done
for name in wrapup continue; do
  install_rendered "$TEMPLATES/commands/$name.md" "$CONFIG_DIR/commands/$name.md"
done
update_agents_md
setup_notes

if [ "$DRY_RUN" -eq 0 ]; then
  printf 'preset=%s\ninstalled=%s\n' "$PRESET" "$STAMP" > "$CONFIG_DIR/.opencode-router-preset"
  cat <<EOF

Done. Next:
  1. Make 'router' your default agent: add  "default_agent": "router"  to $CONFIG_DIR/opencode.json
     (or press Tab in opencode to pick it each time).
  2. Restart opencode.
  3. Run the checks in the README, section "Check that it works".
EOF
fi
