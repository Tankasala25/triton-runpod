# ---- Triton base only (includes CUDA + cuDNN + TensorRT + backends) ----
ARG TRITON_VERSION=24.09
FROM nvcr.io/nvidia/tritonserver:${TRITON_VERSION}-py3

# System tools (persist across restarts because they’re in the image)
# - iproute2: provides `ss`
# - net-tools: provides `netstat`
# - lsof: open file/port inspection
# - curl, git, jq, ca-certificates: handy utilities
# - tini: clean PID 1 init for signal handling/zombies
RUN apt-get update && apt-get install -y --no-install-recommends \
      iproute2 net-tools lsof \
      ca-certificates curl git jq tini \
    && rm -rf /var/lib/apt/lists/*

# Python tools: Triton client + Jupyter + basics
RUN python3 -m pip install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir \
      "tritonclient[http,grpc]" \
      jupyterlab pillow requests && \
    pip cache purge

# Workspace (/workspace is persistent on RunPod)
ENV MODEL_REPO=/workspace/models
WORKDIR /workspace

# Expose ports (Triton HTTP/gRPC/metrics + Jupyter)
EXPOSE 8000 8001 8002 8888

# Entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/usr/local/bin/entrypoint.sh","start-all"]
