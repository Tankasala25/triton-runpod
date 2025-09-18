# ---- Triton base (CUDA + cuDNN + TensorRT + backends included) ----
ARG TRITON_VERSION=24.09
FROM nvcr.io/nvidia/tritonserver:${TRITON_VERSION}-py3

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

# System tools (persist in the image)
# - iproute2(ss), net-tools(netstat), lsof: debugging
# - curl, git, jq, ca-certificates: utilities
# - tini: clean PID 1 (signal handling/zombies)
RUN apt-get update && apt-get install -y --no-install-recommends \
      iproute2 net-tools lsof \
      ca-certificates curl git jq tini \
    && rm -rf /var/lib/apt/lists/*

# Python tools:
# - Triton client HTTP/gRPC
# - JupyterLab + jupyter_server + classic notebook server
# - ipykernel (register kernel under sys-prefix so Jupyter finds it)
# - pillow/requests: handy libs for demos
RUN python3 -m pip install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir \
      "tritonclient[http,grpc]" \
      jupyterlab jupyter_server notebook ipykernel \
      pillow requests && \
    python3 -m ipykernel install --sys-prefix --name=python3 --display-name="Python 3" && \
    pip cache purge

# Workspace (/workspace is the persistent volume on RunPod)
ENV MODEL_REPO=/workspace/models
WORKDIR /workspace

# Ports (Triton HTTP/gRPC/metrics + Jupyter)
EXPOSE 8000 8001 8002 8888

# Entrypoint script (handles smart port binding + Jupyter no-auth)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Healthcheck: Triton HTTP readiness (waits for entrypoint to start it)
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD curl -fsS http://127.0.0.1:8000/v2/health/ready || exit 1

ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/usr/local/bin/entrypoint.sh","start-all"]
