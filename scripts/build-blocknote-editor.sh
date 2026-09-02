#!/bin/zsh
set -euo pipefail

# Rebuilds the BlockNote editor's web bundle and copies it into
# Sources/ClassroomApp/Resources/BlockNoteEditor so `swift build` never
# needs Node — only rerunning this script does, after editing
# webviews/blocknote-editor/src. See
# updates/2026-09-02 BLOCKNOTE-EDITOR - OPEN/update.md.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="$ROOT_DIR/webviews/blocknote-editor"
DEST_DIR="$ROOT_DIR/Sources/ClassroomApp/Resources/BlockNoteEditor"

cd "$WEB_DIR"
if [[ ! -d node_modules ]]; then
    npm install
fi
npm run build

rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"
cp -R dist/. "$DEST_DIR"/

echo "Copied $WEB_DIR/dist -> $DEST_DIR"
