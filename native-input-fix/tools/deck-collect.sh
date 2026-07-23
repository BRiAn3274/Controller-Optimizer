#!/usr/bin/env bash
set -euo pipefail

deck_host=${DECK_HOST:-deck@192.168.1.235}
deck_key=${DECK_KEY:-/Users/a1/.ssh/controller_optimizer_deck_ed25519}
project_root=$(cd "$(dirname "$0")/.." && pwd)
output_dir="$project_root/output/deck-diagnostics"
mkdir -p "$output_dir"

remote_state='.local/share/Steam/steamapps/compatdata/250900/pfx/drive_c/users/steamuser/AppData/Local/IsaacNativeInputFix'
scp -i "$deck_key" -r "$deck_host:$remote_state/." "$output_dir/"
echo "Collected diagnostics in $output_dir"
