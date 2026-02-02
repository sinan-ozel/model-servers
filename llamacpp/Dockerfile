FROM ghcr.io/ggml-org/llama.cpp:server-cuda

# Copy model into image (large layer!)
# This will be replaced during build with actual model
COPY model.gguf /models/model.gguf

EXPOSE 8080

# Default CMD - can be overridden with docker run
CMD ["-m", "/models/model.gguf", \
     "--host", "0.0.0.0", \
     "--port", "8080", \
     "-ngl", "999", \
     "-c", "4096"]
