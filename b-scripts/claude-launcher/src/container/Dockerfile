FROM node:20-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends git ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    npm install -g @anthropic-ai/claude-code && \
    npm cache clean --force

WORKDIR /workspace

ENTRYPOINT ["claude"]
