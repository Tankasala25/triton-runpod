#!/usr/bin/env bash
set -euo pipefail

# Defaults (can be overridden by env vars)
: "${MODEL_REPO:=/workspace/models}"
: "${RUN_JUPYTER:=true}"
: "${JUPYTER_PORT:=8888}"
: "${TRITON_ARGS:=--log-verbose=1}"

# Safer defaults for Jupyter: no auth only if SG restricts your IP
JUPYTER_ARGS="--ip=0.0.0.0 --port=${JUPYTER_PORT} --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password=''"

echo "[entrypoint] MODEL_REPO=${MODEL_REPO}"
echo "[entrypoint] RUN_JUPYTER=${RUN_JUPYTER}"
echo "[entrypoint] JUPYTER_PORT=${JUPYTER_PORT}"
echo "[entrypoint] TRITON_ARGS=${TRITON_ARGS}"

mkdir -p "${MODEL_REPO}"

start_triton() {
  echo "[entrypoint] Starting Triton Inference Server..."
  tritonserver --model-repository="${MODEL_REPO}" ${TRITON_ARGS} &
  TRITON_PID=$!
  echo "[entrypoint] Triton PID: ${TRITON_PID}"
}

start_jupyter() {
  echo "[entrypoint] Starting JupyterLab on 0.0.0.0:${JUPYTER_PORT}"
  jupyter lab ${JUPYTER_ARGS} &
  JUPYTER_PID=$!
  echo "[entrypoint] JupyterLab PID: ${JUPYTER_PID}"
}

case "${1:-start-all}" in
  start-triton)
    start_triton
    wait "${TRITON_PID}"
    ;;
  start-jupyter)
    start_jupyter
    wait "${JUPYTER_PID}"
    ;;
  start-all)
    start_triton
    if [[ "${RUN_JUPYTER,,}" == "true" ]]; then
      start_jupyter
      # Wait for whichever exits first
      wait -n "${TRITON_PID}" "${JUPYTER_PID}"
    else
      wait "${TRITON_PID}"
    fi
    ;;
  *)
    echo "[entrypoint] Executing custom command: $*"
    exec "$@"
    ;;
esac

echo "[entrypoint] A background service exited. Keeping container alive for debugging…"
tail -f /dev/null
