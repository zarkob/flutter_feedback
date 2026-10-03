#!/usr/bin/env bash
# Contract check: the package client against the local relay server.
#
# The relay runs on a free local port with a fake backlog and a fake image
# host. No real issue is filed and no real image is uploaded.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$here/.." && pwd)"
relay_dir="$(cd "$package_dir/../relay" && pwd)"
port="${1:-8791}"

cd "$relay_dir"
node src/local_server.ts --port "$port" >"$package_dir/build/local_relay.log" 2>&1 &
relay_pid=$!
trap 'kill "$relay_pid" 2>/dev/null || true' EXIT

for _ in $(seq 1 40); do
  if curl -s -o /dev/null "http://127.0.0.1:$port/reports/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee" -H 'X-Tester-Token: local-tester-token'; then
    break
  fi
  sleep 0.25
done

cd "$package_dir"
dart run tool/server_contract_check.dart --url "http://127.0.0.1:$port"
