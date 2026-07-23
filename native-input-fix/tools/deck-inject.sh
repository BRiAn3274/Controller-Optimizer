#!/usr/bin/env bash
set -euo pipefail

deck_host=${DECK_HOST:-deck@192.168.1.235}
deck_key=${DECK_KEY:-/Users/a1/.ssh/controller_optimizer_deck_ed25519}
remote_stage='.local/share/Steam/steamapps/common/The Binding of Isaac Rebirth/IsaacNativeInputFix'

ssh -i "$deck_key" "$deck_host" "
  set -eu
  pgrep -f '[i]saac-ng.exe' >/dev/null || { echo 'isaac-ng.exe is not running' >&2; exit 10; }
  export STEAM_COMPAT_DATA_PATH=\"\$HOME/.local/share/Steam/steamapps/compatdata/250900\"
  export STEAM_COMPAT_CLIENT_INSTALL_PATH=\"\$HOME/.local/share/Steam\"
  proton=\"\$HOME/.local/share/Steam/steamapps/common/Proton 9.0 (Beta)/proton\"
  stage=\"\$HOME/$remote_stage\"
  \"\$proton\" run \"\$stage/IsaacInputInjector.exe\" \
    'Z:\\home\\deck\\.local\\share\\Steam\\steamapps\\common\\The Binding of Isaac Rebirth\\IsaacNativeInputFix\\azazel_input_hook_current.dll'
"

echo 'Payload injector completed. Check diagnostics.json before testing.'
