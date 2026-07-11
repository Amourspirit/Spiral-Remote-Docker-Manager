#!/usr/bin/env bash
set -eu

APP_DIR=${ENTRY_POINT_APP_DIR:-/app}

cleanup_ran=0
child_pid=""

log() {
  echo "[entrypoint] $*"
}

is_enabled() {
  # Defaults to enabled when unset; accepts common false-like values.
  case "${1:-true}" in
    0|false|FALSE|no|NO|off|OFF)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

cleanup() {
  if [ "$cleanup_ran" -eq 1 ]; then
    return
  fi
  cleanup_ran=1

  if ! is_enabled "${ROUTE_DISABLE_ON_STOP:-true}"; then
    log "Skipping route disable on stop (ROUTE_DISABLE_ON_STOP=${ROUTE_DISABLE_ON_STOP:-true})."
    return
  fi

  log "Disabling Cloudflare route..."
  if "$APP_DIR/tunnel_route.sh" disable; then
    log "Cloudflare route disable completed."
  else
    log "Cloudflare route disable failed."
  fi
}

on_term() {
  log "Termination signal received."
  if [ -n "$child_pid" ]; then
    kill -TERM "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
  fi
  cleanup
  exit 0
}

trap 'on_term' INT TERM
trap 'cleanup' EXIT

if is_enabled "${ROUTE_ENABLE_ON_START:-true}"; then
  log "Enabling Cloudflare route..."
  if "$APP_DIR/tunnel_route.sh" enable; then
    log "Cloudflare route enable completed."
  else
    log "Cloudflare route enable failed; exiting."
    exit 1
  fi
else
  log "Skipping route enable on start (ROUTE_ENABLE_ON_START=${ROUTE_ENABLE_ON_START:-true})."
fi

if [ "$#" -eq 0 ]; then
  log "No command provided; container will stay alive."
  while :; do
    sleep 2 &
    child_pid="$!"
    wait "$child_pid"
    child_pid=""
  done
else
  log "Running command: $*"
  "$@" &
  child_pid="$!"
  wait "$child_pid"
  child_pid=""
fi
