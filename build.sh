#!/usr/bin/env bash
# Forwarder script
exec "$(dirname "$0")/scripts/build_firmware.sh" "$@"
