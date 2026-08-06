#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && ! -d "$1" ) ]]; then
  echo "usage: $0 [/path/to/IsaacNativeInputFix]" >&2
  exit 2
fi

package_dir=${1:-$(cd "$(dirname "$0")/.." && pwd)}
package_dir=$(cd "$package_dir" && pwd)
[[ -f "$package_dir/IsaacInputUnpatcher.exe" ]] || {
  echo "missing IsaacInputUnpatcher.exe" >&2
  exit 3
}

deck_host=${DECK_HOST:-deck@192.168.1.235}
deck_key=${DECK_KEY:-/Users/a1/.ssh/controller_optimizer_deck_ed25519}
remote_steam_rel=${DECK_STEAM_REL:-.local/share/Steam}
remote_isaac_rel=${DECK_ISAAC_REL:-.local/share/Steam/steamapps/common/The Binding of Isaac Rebirth}
remote_compat_rel=${DECK_COMPATDATA_REL:-.local/share/Steam/steamapps/compatdata/250900}
remote_proton_rel=${DECK_PROTON_REL:-.local/share/Steam/steamapps/common/Proton 9.0 (Beta)/proton}
remote_stage_rel=${DECK_STAGE_REL:-.local/share/IsaacNativeInputFix}
deck_home=${DECK_HOME:-/home/deck}

deck_home_win=${deck_home//\//\\}
isaac_rel_win=${remote_isaac_rel//\//\\}
game_win=${DECK_GAME_WIN:-"Z:${deck_home_win}\\${isaac_rel_win}\\isaac-ng.exe"}

ssh -i "$deck_key" "$deck_host" "
  set -eu
  if pgrep -f '[i]saac-ng.exe' >/dev/null; then
    echo 'Isaac is running; close it before uninstalling the persistent loader.' >&2
    exit 10
  fi
  stage=\"\$HOME/$remote_stage_rel\"
  proton=\"\$HOME/$remote_proton_rel\"
  export STEAM_COMPAT_DATA_PATH=\"\$HOME/$remote_compat_rel\"
  export STEAM_COMPAT_CLIENT_INSTALL_PATH=\"\$HOME/$remote_steam_rel\"
  \"\$proton\" run \"\$stage/IsaacInputUnpatcher.exe\" /silent '$game_win'
"

echo "Persistent loader removed from $deck_host. Staged helper files were retained for recovery or reinstall."
