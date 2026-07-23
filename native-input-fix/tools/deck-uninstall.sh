#!/usr/bin/env bash
set -euo pipefail

deck_host=${DECK_HOST:-deck@192.168.1.235}
deck_key=${DECK_KEY:-/Users/a1/.ssh/controller_optimizer_deck_ed25519}
remote_game='.local/share/Steam/steamapps/common/The Binding of Isaac Rebirth'

ssh -i "$deck_key" "$deck_host" "
  set -eu
  game=\"\$HOME/$remote_game\"
  stage=\"\$game/IsaacNativeInputFix\"
  if pgrep -f '[i]saac-ng.exe' >/dev/null; then echo 'game is running' >&2; exit 10; fi
  [ -f \"\$stage/staged.sha256\" ] || { echo 'staging manifest missing; refusing removal' >&2; exit 11; }
  (cd \"\$stage\" && sha256sum -c staged.sha256)
  rm \"\$stage/azazel_input_hook_current.dll\" \"\$stage/IsaacInputInjector.exe\" \
    \"\$stage/staged.sha256\"
"
echo 'Removed the verified staged project binaries; configuration and logs were retained.'
