#!/usr/bin/env bash
# Forwarder script
exec "$(dirname "$0")/scripts/run_firmware.sh" "$@"
