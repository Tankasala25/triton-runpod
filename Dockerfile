# ---- Triton base only (includes CUDA + backends) ----
ARG TRITON_VERSION=24.09
FROM nvcr.io/nvidia/tritonserver:${TRITON_VERSION}-py3

# Basics
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git tini jq && \
    rm -rf /var/lib/apt/lists/*

# Python tools: Triton client + Jupyter + utils
RUN python3 -m pip install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir \
      "tritonclient[http,grpc]" \
      jupyterlab pillow requests && \
    pip cache purge

# Workspace (/workspace is persistent on RunPod)
ENV MODEL_REPO=/workspace/models
WORKDIR /workspace

# Triton HTTP/gRPC/metrics + Jupyter
EXPOSE 8000 8001 8002 8888

# Entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/usr/local/bin/entrypoint.sh","start-all"]
