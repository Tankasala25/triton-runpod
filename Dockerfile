# ---------- Stage 1: pull Triton binaries from NVIDIA's official image ----------
ARG TRITON_VERSION=24.09
FROM nvcr.io/nvidia/tritonserver:${TRITON_VERSION}-py3 AS triton

# ---------- Stage 2: extend RunPod's PyTorch base with Triton + tools ----------
FROM runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04

# Minimal OS deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git tini jq && \
    rm -rf /var/lib/apt/lists/*

# Copy Triton Server runtime from the official image
COPY --from=triton /opt/tritonserver /opt/tritonserver
# (Optional convenience scripts that ship in the Triton image)
COPY --from=triton /usr/local/bin /usr/local/bin

# Make Triton visible
ENV PATH=/opt/tritonserver/bin:${PATH}
ENV LD_LIBRARY_PATH=/opt/tritonserver/lib:${LD_LIBRARY_PATH}

# Python packages:
# - tritonclient: test from same container (http or grpc)
# - jupyterlab: notebooks (port 8888)
# - pillow/requests: helpers
# - tensorflow-cpu: optional for notebook experiments (Triton can serve TF SavedModels without TF installed)
# - transformers/datasets: optional, handy for demos (comment out if you want a smaller image)
RUN python3 -m pip install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir \
      "tritonclient[http,grpc]" \
      jupyterlab \
      pillow requests \
      tensorflow-cpu \
      transformers datasets && \
    pip cache purge

# Defaults for RunPod persistent workspace
ENV MODEL_REPO=/workspace/models
WORKDIR /workspace

# Expose Triton (HTTP/gRPC/Metrics) + Jupyter
EXPOSE 8000 8001 8002 8888

# Runtime toggles
ENV RUN_JUPYTER=true
ENV JUPYTER_PORT=8888
ENV TRITON_ARGS=""

# Entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Use tini to reap zombies, then our script
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/entrypoint.sh", "start-all"]
