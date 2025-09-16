#!/usr/bin/env bash
set -euo pipefail

: "${MODEL_REPO:=/workspace/models}"
: "${RUN_JUPYTER:=true}"
: "${JUPYTER_PORT:=8888}"
: "${TRITON_ARGS:=--log-verbose=1}"

JUPYTER_ARGS="--ip=0.0.0.0 --port=${JUPYTER_PORT} --allow-root --no-browser \
  --NotebookApp.token='' --NotebookApp.password=''"

echo "[entrypoint] MODEL_REPO=${MODEL_REPO}"
mkdir -p "${MODEL_REPO}"

start_triton() {
  echo "[entrypoint] Starting Triton…"
  tritonserver --model-repository="${MODEL_REPO}" ${TRITON_ARGS} &
  TRITON_PID=$!
}

start_jupyter() {
  if [[ "${RUN_JUPYTER,,}" == "true" ]]; then
    echo "[entrypoint] Starting JupyterLab on :${JUPYTER_PORT}"
    jupyter lab ${JUPYTER_ARGS} &
    JUPYTER_PID=$!
  fi
}

case "${1:-start-all}" in
  start-triton)  start_triton;  wait "${TRITON_PID}";;
  start-jupyter) start_jupyter; wait "${JUPYTER_PID}";;
  start-all)     start_triton; start_jupyter; wait -n "${TRITON_PID:-0}" "${JUPYTER_PID:-0}";;
  *) echo "[entrypoint] exec $*"; exec "$@";;
esac

echo "[entrypoint] A background service exited; keeping container alive…"
tail -f /dev/null
