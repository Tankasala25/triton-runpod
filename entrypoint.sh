#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Defaults (override via env)
# -----------------------------
: "${MODEL_REPO:=/workspace/models}"
: "${RUN_JUPYTER:=true}"

# Triton ports (HTTP/gRPC/metrics)
: "${TRITON_HTTP_PORT:=8000}"    # required; don’t set to 0
: "${TRITON_GRPC_PORT:=8001}"    # set to 0 to disable
: "${TRITON_METRICS_PORT:=8002}" # set to 0 to disable

# Jupyter settings
: "${JUPYTER_PORT:=8888}"
# Auth controls (empty = no auth)
: "${JUPYTER_TOKEN:=}"
: "${JUPYTER_PASSWORD:=}"
# Proxy/CORS & XSRF (tuned for RunPod)
: "${JUPYTER_ALLOW_ORIGIN_PAT:=https?://.*\.proxy\.runpod\.net}"
: "${JUPYTER_DISABLE_XSRF:=true}"   # set to "false" to re-enable XSRF

# Extra args to Triton (verbosity etc.)
: "${TRITON_EXTRA_ARGS:=--log-verbose=1}"

# Optional: verbose fallback for port checks (default: false)
: "${PORTCHECK_VERBOSE:=false}"

# -----------------------------
# Helpers
# -----------------------------
log() { echo "[entrypoint] $*"; }

port_free() {
  # Return 0 if port is free, 1 if taken. Port "0" means disabled.
  local port="$1"
  [[ "$port" == "0" ]] && return 1

  if command -v ss >/dev/null 2>&1; then
    ! ss -ltn "( sport = :$port )" | grep -q ":$port"
  elif command -v netstat >/dev/null 2>&1; then
    ! netstat -ltn | grep -q ":$port "
  else
    # Fallback: try to open a TCP socket.
    if [[ "${PORTCHECK_VERBOSE,,}" == "true" ]]; then
      log "Fallback port check via /dev/tcp for :${port}"
      (exec 3<>/dev/tcp/127.0.0.1/"$port") && { exec 3>&- 3<&-; return 1; } || return 0
    else
      (exec 3<>/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1 && { exec 3>&- 3<&-; return 1; } || return 0
    fi
  fi
}

# Ensure model repo exists (persists on RunPod volume)
mkdir -p "${MODEL_REPO}"

# Build Triton args
TRITON_ARGS=( "--model-repository=${MODEL_REPO}" ${TRITON_EXTRA_ARGS} )

# HTTP (required)
if [[ "${TRITON_HTTP_PORT}" == "0" ]]; then
  log "ERROR: HTTP port cannot be 0; Triton HTTP is required."
  exit 1
fi
if port_free "${TRITON_HTTP_PORT}"; then
  TRITON_ARGS+=("--http-port=${TRITON_HTTP_PORT}")
else
  log "ERROR: HTTP port ${TRITON_HTTP_PORT} is busy. Aborting."
  { ss -ltn || netstat -ltn || true; } 2>/dev/null
  exit 1
fi

# gRPC (optional)
if [[ "${TRITON_GRPC_PORT}" != "0" ]]; then
  if port_free "${TRITON_GRPC_PORT}"; then
    TRITON_ARGS+=("--grpc-port=${TRITON_GRPC_PORT}")
  else
    log "gRPC port ${TRITON_GRPC_PORT} busy; disabling gRPC."
    TRITON_ARGS+=("--grpc-port=0")
  fi
else
  TRITON_ARGS+=("--grpc-port=0")
fi

# Metrics (optional)
if [[ "${TRITON_METRICS_PORT}" != "0" ]]; then
  if port_free "${TRITON_METRICS_PORT}"; then
    TRITON_ARGS+=("--metrics-port=${TRITON_METRICS_PORT}")
  else
    log "Metrics port ${TRITON_METRICS_PORT} busy; disabling metrics."
    TRITON_ARGS+=("--allow-metrics=false")
  fi
else
  TRITON_ARGS+=("--allow-metrics=false")
fi

start_triton() {
  log "Starting Triton with args:"
  printf '  %q\n' tritonserver "${TRITON_ARGS[@]}"
  tritonserver "${TRITON_ARGS[@]}" &
  TRITON_PID=$!
  log "Triton PID: ${TRITON_PID}"
}

start_jupyter() {
  if [[ "${RUN_JUPYTER,,}" == "true" ]]; then
    # Prefer ServerApp flags (modern Jupyter). Allow RunPod proxy origin; XSRF toggleable.
    local args=(
      --ServerApp.ip=0.0.0.0
      --ServerApp.port="${JUPYTER_PORT}"
      --ServerApp.allow_root=True
      --ServerApp.root_dir=/workspace
      --ServerApp.preferred_dir=/workspace
      --ServerApp.base_url='/'
      --ServerApp.trust_xheaders=True
      --ServerApp.allow_remote_access=True
      --ServerApp.allow_origin_pat="${JUPYTER_ALLOW_ORIGIN_PAT}"
      --no-browser
    )

    # Auth: empty token/password means no-auth
    if [[ -n "${JUPYTER_TOKEN}" ]]; then
      args+=(--ServerApp.token="${JUPYTER_TOKEN}")
    else
      args+=(--ServerApp.token='')
    fi
    if [[ -n "${JUPYTER_PASSWORD}" ]]; then
      # Expect a hashed password if supplied; empty means none
      args+=(--ServerApp.password="${JUPYTER_PASSWORD}")
    else
      args+=(--ServerApp.password='')
    fi

    # XSRF toggle (disabled by default for RunPod proxy)
    if [[ "${JUPYTER_DISABLE_XSRF,,}" == "true" ]]; then
      args+=(--ServerApp.disable_check_xsrf=True)
      log "Starting JupyterLab on :${JUPYTER_PORT} (no auth by default; CORS open to RunPod proxy; XSRF disabled)"
    else
      log "Starting JupyterLab on :${JUPYTER_PORT} (CORS open to RunPod proxy; XSRF enabled)"
    fi

    # Launch
    python3 -m jupyterlab "${args[@]}" &
    JUPYTER_PID=$!
    log "Jupyter PID: ${JUPYTER_PID}"
  else
    log "RUN_JUPYTER=false — skipping Jupyter."
  fi
}

case "${1:-start-all}" in
  start-triton)  start_triton;  wait "${TRITON_PID}";;
  start-jupyter) start_jupyter; wait "${JUPYTER_PID}";;
  start-all)     start_triton; start_jupyter; wait -n "${TRITON_PID:-0}" "${JUPYTER_PID:-0}";;
  *) log "exec $*"; exec "$@";;
esac

log "A background service exited. Keeping container alive for debugging…"
tail -f /dev/null
