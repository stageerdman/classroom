#!/bin/zsh
set -euo pipefail

# Rebuilds the BlockNote spike's web bundle and copies it into
# Sources/ClassroomApp/Resources/BlockNoteSpike so `swift build` never
# needs Node — only rerunning this script does, after editing
# webviews/blocknote-spike/src. See
# updates/2026-09-02 BLOCKNOTE-SPIKE - OPEN/update.md.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="$ROOT_DIR/webviews/blocknote-spike"
DEST_DIR="$ROOT_DIR/Sources/ClassroomApp/Resources/BlockNoteSpike"

cd "$WEB_DIR"
if [[ ! -d node_modules ]]; then
    npm install
fi
npm run build

rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"
cp -R dist/. "$DEST_DIR"/

echo "Copied $WEB_DIR/dist -> $DEST_DIR"
