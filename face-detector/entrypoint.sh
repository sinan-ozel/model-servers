#!/usr/bin/env bash
set -e

MODE="${1:-serve}"

case "$MODE" in
  serve|http)
    exec uvicorn src.http.app:app --host 0.0.0.0 --port 8080
    ;;
  mcp)
    exec python3 -m src.mcp.server
    ;;
  detect|cli)
    shift
    exec python3 -m src.cli.main "$@"
    ;;
  *)
    echo "Unknown mode: $MODE (expected: serve|mcp|detect)" >&2
    exit 1
    ;;
esac
