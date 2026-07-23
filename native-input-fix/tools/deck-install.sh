#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || ! -d "$1" ]]; then
  echo "usage: $0 /path/to/IsaacNativeInputFix [generic-test|tainted-test]" >&2
  exit 2
fi

package_dir=$(cd "$1" && pwd)
mode=${2:-tainted-test}
case "$mode" in generic-test|tainted-test) ;; *) echo "unsupported mode: $mode" >&2; exit 2 ;; esac
for file in azazel_input_hook.dll IsaacInputInjector.exe "config/$mode.ini"; do
  [[ -f "$package_dir/$file" ]] || { echo "missing $file" >&2; exit 3; }
done

deck_host=${DECK_HOST:-deck@192.168.1.235}
deck_key=${DECK_KEY:-/Users/a1/.ssh/controller_optimizer_deck_ed25519}
remote_stage='.local/share/Steam/steamapps/common/The Binding of Isaac Rebirth/IsaacNativeInputFix'
remote_state='.local/share/Steam/steamapps/compatdata/250900/pfx/drive_c/users/steamuser/AppData/Local/IsaacNativeInputFix'

ssh -i "$deck_key" "$deck_host" "
  set -eu
  if pgrep -f '[i]saac-ng.exe' >/dev/null; then echo 'game is running' >&2; exit 10; fi
  mkdir -p \"\$HOME/$remote_stage\" \"\$HOME/$remote_state\"
"
scp -i "$deck_key" "$package_dir/IsaacInputInjector.exe" \
  "$deck_host:$remote_stage/IsaacInputInjector.exe"
scp -i "$deck_key" "$package_dir/azazel_input_hook.dll" \
  "$deck_host:$remote_stage/azazel_input_hook_current.dll"
scp -i "$deck_key" "$package_dir/config/$mode.ini" \
  "$deck_host:$remote_state/config.ini"
ssh -i "$deck_key" "$deck_host" "
  set -eu
  stage=\"\$HOME/$remote_stage\"
  cd \"\$stage\"
  sha256sum azazel_input_hook_current.dll IsaacInputInjector.exe > staged.sha256
"

echo "Staged $mode. Start Isaac normally through Steam, then run deck-inject.sh."
