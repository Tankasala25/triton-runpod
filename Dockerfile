# ---- Triton base (CUDA + cuDNN + TensorRT + backends included) ----
ARG TRITON_VERSION=24.09
FROM nvcr.io/nvidia/tritonserver:${TRITON_VERSION}-py3

# Prevent interactive apt, speed up pip logs
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

# System tools useful for debugging + tini for clean PID1
RUN apt-get update && apt-get install -y --no-install-recommends \
      iproute2 net-tools lsof \
      ca-certificates curl git jq tini \
    && rm -rf /var/lib/apt/lists/*

# Python tooling:
# - Triton client libs
# - JupyterLab stack (pinned to stable major versions)
# - ipykernel (registers a kernel so Jupyter sees Python 3)
# - common demo libs
RUN python3 -m pip install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir \
      "tritonclient[http,grpc]" \
      "jupyterlab>=4,<5" "jupyter_server>=2,<3" "notebook>=7,<8" ipykernel \
      pillow requests && \
    python3 -m ipykernel install --sys-prefix --name=python3 --display-name="Python 3" && \
    pip cache purge

# Workspace (RunPod usually mounts /workspace as a persistent volume)
ENV MODEL_REPO=/workspace/models
WORKDIR /workspace
RUN mkdir -p "$MODEL_REPO"

# Ports: Triton (HTTP/GRPC/Metrics) + Jupyter
EXPOSE 8000 8001 8002 8888

# Copy entrypoint and mark executable
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Healthcheck: Triton HTTP readiness
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD curl -fsS http://127.0.0.1:8000/v2/health/ready || exit 1

# Use tini as PID 1 for clean signal handling
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/usr/local/bin/entrypoint.sh","start-all"]
