#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Defaults (override via env)
# -----------------------------
: "${MODEL_REPO:=/workspace/models}"
: "${RUN_JUPYTER:=true}"

# Triton ports (HTTP required)
: "${TRITON_HTTP_PORT:=8000}"     # must not be 0
: "${TRITON_GRPC_PORT:=8001}"     # set 0 to disable
: "${TRITON_METRICS_PORT:=8002}"  # set 0 to disable

# Jupyter settings
: "${JUPYTER_PORT:=8888}"

# Auth controls — leave EMPTY to fully disable auth
: "${JUPYTER_TOKEN:=}"                 # ServerApp.token
: "${JUPYTER_PASSWORD:=}"              # ServerApp.password (sha1 if used)
: "${JUPYTER_IDENTITY_TOKEN:=}"        # IdentityProvider.token (Jupyter Server 2)

# CORS/Proxy/XSRF — tuned for RunPod *.proxy.runpod.net
: "${JUPYTER_ALLOW_ORIGIN_PAT:=https?://.*\.proxy\.runpod\.net}"
: "${JUPYTER_DISABLE_XSRF:=true}"

# Extra args to Triton (verbosity, etc.)
: "${TRITON_EXTRA_ARGS:=--log-verbose=1}"

log() { echo "[entrypoint] $*"; }

port_free() {
  # Return 0 if port is free, 1 if busy; "0" means feature disabled.
  local port="$1"
  [[ "$port" == "0" ]] && return 1
  if command -v ss >/dev/null 2>&1; then
    ! ss -ltn "( sport = :$port )" | grep -q ":$port"
  else
    ! netstat -ltn 2>/dev/null | grep -q ":$port "
  fi
}

# Ensure model repo exists
mkdir -p "${MODEL_REPO}"

# ---- Build Triton args ----
TRITON_ARGS=( "--model-repository=${MODEL_REPO}" ${TRITON_EXTRA_ARGS} )

# HTTP (required)
if [[ "${TRITON_HTTP_PORT}" == "0" ]]; then
  log "ERROR: TRITON_HTTP_PORT cannot be 0."
  exit 1
fi
if port_free "${TRITON_HTTP_PORT}"; then
  TRITON_ARGS+=("--http-port=${TRITON_HTTP_PORT}")
else
  log "ERROR: HTTP port ${TRITON_HTTP_PORT} is busy. Aborting."
  (ss -ltn || netstat -ltn || true) 2>/dev/null
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
  if [[ "${RUN_JUPYTER,,}" != "true" ]]; then
    log "RUN_JUPYTER=false — skipping Jupyter."
    return
  fi

  # Build Jupyter args (modern ServerApp flags)
  local args=(
    --ServerApp.ip=0.0.0.0
    --ServerApp.port="${JUPYTER_PORT}"
    --ServerApp.allow_root=True
    --ServerApp.root_dir=/workspace
    --ServerApp.preferred_dir=/workspace
    --ServerApp.base_url=/
    --ServerApp.trust_xheaders=True
    --ServerApp.allow_remote_access=True
    --ServerApp.allow_origin_pat="${JUPYTER_ALLOW_ORIGIN_PAT}"
    --no-browser
  )

  # Auth OFF unless you explicitly set envs
  if [[ -n "${JUPYTER_TOKEN}" ]]; then
    args+=(--ServerApp.token="${JUPYTER_TOKEN}")
  else
    args+=(--ServerApp.token=)
  fi
  if [[ -n "${JUPYTER_PASSWORD}" ]]; then
    args+=(--ServerApp.password="${JUPYTER_PASSWORD}")
  else
    args+=(--ServerApp.password=)
  fi
  if [[ -n "${JUPYTER_IDENTITY_TOKEN}" ]]; then
    args+=(--IdentityProvider.token="${JUPYTER_IDENTITY_TOKEN}")
  else
    args+=(--IdentityProvider.token=)
  fi

  # Compatibility flags (ignored by modern server but harmless)
  [[ -n "${JUPYTER_TOKEN}"    ]] && args+=(--NotebookApp.token="${JUPYTER_TOKEN}")    || args+=(--NotebookApp.token=)
  [[ -n "${JUPYTER_PASSWORD}" ]] && args+=(--NotebookApp.password="${JUPYTER_PASSWORD}") || args+=(--NotebookApp.password=)

  # Disable XSRF for proxy friendliness (prevents 403/cross-origin websocket issues)
  if [[ "${JUPYTER_DISABLE_XSRF,,}" == "true" ]]; then
    args+=(--ServerApp.disable_check_xsrf=True)
    log "Starting JupyterLab :${JUPYTER_PORT} — auth disabled, CORS open to RunPod, XSRF disabled."
  else
    log "Starting JupyterLab :${JUPYTER_PORT} — CORS open to RunPod, XSRF enabled."
  fi

  # Launch
  python3 -m jupyterlab "${args[@]}" &
  JUPYTER_PID=$!
  log "Jupyter PID: ${JUPYTER_PID}"
}

case "${1:-start-all}" in
  start-triton)  start_triton;  wait "${TRITON_PID}";;
  start-jupyter) start_jupyter; wait "${JUPYTER_PID}";;
  start-all)     start_triton; start_jupyter; wait -n "${TRITON_PID:-0}" "${JUPYTER_PID:-0}";;
  *) log "exec $*"; exec "$@";;
esac

log "A background service exited. Keeping container alive for debugging…"
tail -f /dev/null
