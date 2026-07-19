#!/usr/bin/env bash
set -euo pipefail

APP_ID="250900"
PUBLISHED_FILE_ID="3731198516"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DRY_RUN=0
ALLOW_DIRTY=0
SKIP_TESTS=0
STEAM_USER="${STEAM_USERNAME:-}"
CHANGE_NOTE=""
NOTE_FILE=""

usage() {
    cat <<'EOF'
Usage: ./tools/upload_workshop.sh [options]

Options:
  --user NAME       Steam account name (never the password)
  --note TEXT       Workshop change note
  --note-file FILE  Read the change note from a file
  --dry-run         Validate and show the generated package without uploading
  --allow-dirty     Permit an upload from an uncommitted worktree
  --skip-tests      Skip the Lua simulation test
  -h, --help        Show this help
EOF
}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            [[ $# -ge 2 ]] || fail "--user requires a value"
            STEAM_USER="$2"
            shift 2
            ;;
        --note)
            [[ $# -ge 2 ]] || fail "--note requires a value"
            CHANGE_NOTE="$2"
            shift 2
            ;;
        --note-file)
            [[ $# -ge 2 ]] || fail "--note-file requires a path"
            NOTE_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --allow-dirty)
            ALLOW_DIRTY=1
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

cd "$ROOT_DIR"

if [[ -f "$ROOT_DIR/.steam-workshop.env" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.steam-workshop.env"
    if [[ -z "$STEAM_USER" ]]; then
        STEAM_USER="${STEAM_USERNAME:-}"
    fi
fi

for required in main.lua metadata.xml ControllerOptimizer_cover.png; do
    [[ -f "$ROOT_DIR/$required" ]] || fail "missing runtime file: $required"
done

METADATA_VERSION="$(sed -n 's:.*<version>\([^<]*\)</version>.*:\1:p' metadata.xml | head -1)"
MAIN_VERSION="$(sed -n 's/^local VERSION = "\([^"]*\)".*/\1/p' main.lua | head -1)"
METADATA_ID="$(sed -n 's:.*<id>\([^<]*\)</id>.*:\1:p' metadata.xml | head -1)"
METADATA_TITLE="$(sed -n 's:.*<name>\([^<]*\)</name>.*:\1:p' metadata.xml | head -1)"
METADATA_DESCRIPTION="$(sed -n '/<description>/,/<\/description>/p' metadata.xml | sed '1s:.*<description>::; $s:</description>.*::')"

[[ -n "$METADATA_VERSION" ]] || fail "could not read metadata.xml version"
[[ -n "$METADATA_TITLE" ]] || fail "could not read metadata.xml name"
[[ -n "$METADATA_DESCRIPTION" ]] || fail "could not read metadata.xml description"
[[ "$METADATA_VERSION" == "$MAIN_VERSION" ]] ||
    fail "version mismatch: main.lua=$MAIN_VERSION metadata.xml=$METADATA_VERSION"
[[ "$METADATA_ID" == "$PUBLISHED_FILE_ID" ]] ||
    fail "Workshop ID mismatch: expected $PUBLISHED_FILE_ID, got $METADATA_ID"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a Git repository"

if [[ "$ALLOW_DIRTY" -eq 0 ]] && [[ -n "$(git status --porcelain)" ]]; then
    fail "Git worktree is dirty; commit the release first or use --allow-dirty"
fi

TAG_NAME="v$METADATA_VERSION"
if git rev-parse -q --verify "refs/tags/$TAG_NAME" >/dev/null; then
    TAG_COMMIT="$(git rev-list -n 1 "$TAG_NAME")"
    HEAD_COMMIT="$(git rev-parse HEAD)"
    [[ "$TAG_COMMIT" == "$HEAD_COMMIT" ]] ||
        fail "$TAG_NAME already points to another commit"
fi

if command -v luac >/dev/null 2>&1; then
    luac -p main.lua
fi

if [[ "$SKIP_TESTS" -eq 0 ]] && [[ -f tests/test_controller_optimizer.lua ]]; then
    if command -v lua >/dev/null 2>&1; then
        lua tests/test_controller_optimizer.lua
    elif command -v luajit >/dev/null 2>&1; then
        luajit tests/test_controller_optimizer.lua
    else
        fail "Lua is required for tests; install Lua or use --skip-tests"
    fi
fi

if [[ -n "$NOTE_FILE" ]]; then
    [[ -f "$NOTE_FILE" ]] || fail "change-note file not found: $NOTE_FILE"
    CHANGE_NOTE="$(tr '\r\n' '  ' < "$NOTE_FILE")"
fi

if [[ -z "$CHANGE_NOTE" ]]; then
    COMMIT_SUBJECT="$(git log -1 --pretty=%s 2>/dev/null || true)"
    CHANGE_NOTE="Controller Optimizer $METADATA_VERSION"
    if [[ -n "$COMMIT_SUBJECT" ]]; then
        CHANGE_NOTE="$CHANGE_NOTE - $COMMIT_SUBJECT"
    fi
fi
CHANGE_NOTE="$(printf '%s' "$CHANGE_NOTE" | tr '\r\n' '  ')"

if [[ -n "${STEAMCMD:-}" ]]; then
    STEAMCMD_BIN="$STEAMCMD"
elif command -v steamcmd >/dev/null 2>&1; then
    STEAMCMD_BIN="$(command -v steamcmd)"
elif [[ -x "$HOME/steamcmd/steamcmd.sh" ]]; then
    STEAMCMD_BIN="$HOME/steamcmd/steamcmd.sh"
elif [[ -x "$HOME/steamcmd/steamcmd" ]]; then
    STEAMCMD_BIN="$HOME/steamcmd/steamcmd"
else
    fail "SteamCMD not found; set STEAMCMD or install it under \$HOME/steamcmd"
fi
[[ -x "$STEAMCMD_BIN" ]] || fail "SteamCMD is not executable: $STEAMCMD_BIN"

STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/controller-optimizer-upload.XXXXXX")"
CONTENT_DIR="$STAGE_ROOT/content"
VDF_FILE="$STAGE_ROOT/workshop_build_item.vdf"
LOG_FILE="$STAGE_ROOT/steamcmd-upload.log"

cleanup() {
    rm -rf -- "$STAGE_ROOT"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$CONTENT_DIR"
cp main.lua metadata.xml ControllerOptimizer_cover.png "$CONTENT_DIR/"

vdf_escape() {
    printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; s/\n/\\n/g'
}

CONTENT_VDF="$(vdf_escape "$CONTENT_DIR")"
PREVIEW_VDF="$(vdf_escape "$CONTENT_DIR/ControllerOptimizer_cover.png")"
NOTE_VDF="$(vdf_escape "$CHANGE_NOTE")"
TITLE_VDF="$(vdf_escape "$METADATA_TITLE")"
DESCRIPTION_VDF="$(vdf_escape "$METADATA_DESCRIPTION")"

cat > "$VDF_FILE" <<EOF
"workshopitem"
{
    "appid"              "$APP_ID"
    "publishedfileid"    "$PUBLISHED_FILE_ID"
    "contentfolder"      "$CONTENT_VDF"
    "previewfile"        "$PREVIEW_VDF"
    "title"              "$TITLE_VDF"
    "description"        "$DESCRIPTION_VDF"
    "changenote"         "$NOTE_VDF"
}
EOF

printf 'Version:        %s\n' "$METADATA_VERSION"
printf 'Workshop item:  %s\n' "$PUBLISHED_FILE_ID"
printf 'SteamCMD:       %s\n' "$STEAMCMD_BIN"
printf 'Change note:    %s\n' "$CHANGE_NOTE"
printf 'Page metadata:  title and description from metadata.xml\n'
printf 'Package files:\n'
find "$CONTENT_DIR" -maxdepth 1 -type f -print | sed 's#^.*/#  - #'

if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '\nDry run complete. No Steam login or upload was attempted.\n'
    exit 0
fi

if [[ -z "$STEAM_USER" ]]; then
    read -r -p "Steam account name: " STEAM_USER
fi
[[ -n "$STEAM_USER" ]] || fail "Steam account name is required"

printf '\nSteamCMD may now request your password and Steam Guard code interactively.\n'
set +e
"$STEAMCMD_BIN" \
    +@ShutdownOnFailedCommand 1 \
    +login "$STEAM_USER" \
    +workshop_build_item "$VDF_FILE" \
    +quit 2>&1 | tee "$LOG_FILE"
STEAM_STATUS=${PIPESTATUS[0]}
set -e

[[ "$STEAM_STATUS" -eq 0 ]] || fail "SteamCMD exited with status $STEAM_STATUS"
if grep -Eiq '(^|[^A-Za-z])(ERROR!|FAILED)([^A-Za-z]|$)' "$LOG_FILE"; then
    fail "SteamCMD reported an upload error"
fi

if ! git rev-parse -q --verify "refs/tags/$TAG_NAME" >/dev/null; then
    if [[ "$ALLOW_DIRTY" -eq 0 ]]; then
        git tag -a "$TAG_NAME" -m "Controller Optimizer $METADATA_VERSION"
        printf 'Created Git tag %s\n' "$TAG_NAME"
    else
        printf 'Skipped Git tag because --allow-dirty was used.\n'
    fi
fi

printf 'Workshop upload completed for version %s.\n' "$METADATA_VERSION"
