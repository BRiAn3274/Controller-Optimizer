#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || ! -d "$1" ]]; then
  echo "usage: $0 /path/to/IsaacNativeInputFix [diagnostic|generic-test|tainted-test]" >&2
  exit 2
fi

package_dir=$(cd "$1" && pwd)
mode=${2:-diagnostic}
case "$mode" in diagnostic|generic-test|tainted-test) ;; *)
  echo "unsupported mode: $mode" >&2
  exit 2
esac

for file in IsaacInputPatcher.exe IsaacInputUnpatcher.exe bootstp.dll azazel_input_hook.dll "config/$mode.ini"; do
  [[ -f "$package_dir/$file" ]] || { echo "missing $file" >&2; exit 3; }
done

deck_host=${DECK_HOST:-deck@192.168.1.235}
deck_key=${DECK_KEY:-/Users/a1/.ssh/controller_optimizer_deck_ed25519}
deck_home=${DECK_HOME:-/home/deck}
remote_steam_rel=${DECK_STEAM_REL:-.local/share/Steam}
remote_isaac_rel=${DECK_ISAAC_REL:-.local/share/Steam/steamapps/common/The Binding of Isaac Rebirth}
remote_compat_rel=${DECK_COMPATDATA_REL:-.local/share/Steam/steamapps/compatdata/250900}
remote_proton_rel=${DECK_PROTON_REL:-.local/share/Steam/steamapps/common/Proton 9.0 (Beta)/proton}
remote_stage_rel=${DECK_STAGE_REL:-.local/share/IsaacNativeInputFix}
remote_state_rel=${DECK_STATE_REL:-.local/share/Steam/steamapps/compatdata/250900/pfx/drive_c/users/steamuser/AppData/Local/IsaacNativeInputFix}

# The patcher is a Win32 program running inside the same Proton prefix as Isaac.
# Keep the Windows target path configurable because the Deck user's home or
# Steam library may differ from the default installation.
deck_home_win=${deck_home//\//\\}
isaac_rel_win=${remote_isaac_rel//\//\\}
game_win=${DECK_GAME_WIN:-"Z:${deck_home_win}\\${isaac_rel_win}\\isaac-ng.exe"}

ssh -i "$deck_key" "$deck_host" "
  set -eu
  if pgrep -f '[i]saac-ng.exe' >/dev/null; then
    echo 'Isaac is running; close it before installing the persistent loader.' >&2
    exit 10
  fi
  test -f \"\$HOME/$remote_isaac_rel/isaac-ng.exe\" || {
    echo 'isaac-ng.exe was not found at the configured Steam path.' >&2
    exit 11
  }
  test -f \"\$HOME/$remote_proton_rel\" || {
    echo 'The configured Proton executable was not found.' >&2
    exit 12
  }
  mkdir -p \"\$HOME/$remote_stage_rel\" \"\$HOME/$remote_state_rel\"
"

scp -i "$deck_key" \
  "$package_dir/IsaacInputPatcher.exe" \
  "$package_dir/IsaacInputUnpatcher.exe" \
  "$package_dir/bootstp.dll" \
  "$package_dir/azazel_input_hook.dll" \
  "$deck_host:$remote_stage_rel/"
scp -i "$deck_key" "$package_dir/config/$mode.ini" \
  "$deck_host:$remote_state_rel/config.ini"

ssh -i "$deck_key" "$deck_host" "
  set -eu
  stage=\"\$HOME/$remote_stage_rel\"
  proton=\"\$HOME/$remote_proton_rel\"
  export STEAM_COMPAT_DATA_PATH=\"\$HOME/$remote_compat_rel\"
  export STEAM_COMPAT_CLIENT_INSTALL_PATH=\"\$HOME/$remote_steam_rel\"
  \"\$proton\" run \"\$stage/IsaacInputPatcher.exe\" /silent '$game_win'
  sha256sum \"\$stage/IsaacInputPatcher.exe\" \"\$stage/bootstp.dll\" \"\$stage/azazel_input_hook.dll\" > \"\$stage/staged.sha256\"
"

echo "Persistent loader installed on $deck_host. Isaac can be started normally from Steam."
echo "To remove it, run deck-persistent-uninstall.sh with the same Deck settings."
