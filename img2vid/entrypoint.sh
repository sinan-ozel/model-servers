#!/usr/bin/env bash
set -e

MODE="${1:-generate}"

case "$MODE" in
  generate|cli)
    shift
    exec python3 -m src.cli.main "$@"
    ;;
  *)
    echo "Unknown mode: $MODE (expected: generate)" >&2
    exit 1
    ;;
esac
