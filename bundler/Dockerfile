# Simplified Dockerfile that uses pre-compiled Rundler binary
# This avoids the ~30min build time of compiling from source

FROM debian:bookworm-slim

WORKDIR /app

# Install runtime dependencies including Caddy for CORS
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    wget \
    bash \
    debian-keyring \
    debian-archive-keyring \
    apt-transport-https \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list \
    && apt-get update \
    && apt-get install -y caddy \
    && rm -rf /var/lib/apt/lists/*

# Download and install pre-built Rundler binary from GitHub releases
# Using v0.9.2 (latest release with paymaster bug fixes)
RUN wget https://github.com/alchemyplatform/rundler/releases/download/v0.9.2/rundler-v0.9.2-x86_64-unknown-linux-gnu.tar.gz && \
    tar -xzf rundler-v0.9.2-x86_64-unknown-linux-gnu.tar.gz && \
    mv rundler /usr/local/bin/rundler && \
    chmod +x /usr/local/bin/rundler && \
    rm rundler-v0.9.2-x86_64-unknown-linux-gnu.tar.gz

# Copy chain spec, Caddyfile, and entrypoint script
# Cache bust: 2025-11-15-v8-add-unsafe-flag
COPY chain-spec.json /app/chain-spec.json
COPY Caddyfile /app/Caddyfile
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Expose the RPC port and metrics port
EXPOSE 3000 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Run the bundler with entrypoint script
ENTRYPOINT ["/app/entrypoint.sh"]
