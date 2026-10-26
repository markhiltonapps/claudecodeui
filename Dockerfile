# Production image for CloudCLI UI (Claude Code UI) on Railway or any Docker host.
# Builds the client + server, installs the Claude Code CLI, and runs as a
# non-root user whose home directory lives on a persistent volume (/data).

FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    ELECTRON_SKIP_BINARY_DOWNLOAD=1 \
    HUSKY=0 \
    CI=true

# Build tools for native modules (node-pty, better-sqlite3, bcrypt) plus the
# everyday CLI tools that Claude Code and the in-app shell expect.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential python3 python3-setuptools \
      git curl ca-certificates openssh-client \
      ripgrep jq sqlite3 zip unzip tree vim-tiny less procps gosu \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI (the UI spawns it for every Claude session).
RUN npm install -g @anthropic-ai/claude-code --no-audit --no-fund

WORKDIR /app

COPY package.json package-lock.json ./
COPY scripts ./scripts
RUN npm ci --include=dev --no-audit --no-fund

COPY . .
RUN npm run build && npm prune --omit=dev --no-audit --no-fund

# Non-root runtime user. HOME is on the volume so ~/.claude (login, sessions),
# ~/.cloudcli (auth.db) and the projects you create all survive redeploys.
RUN groupadd -r cloudcli && useradd -r -g cloudcli -m -d /home/cloudcli -s /bin/bash cloudcli \
    && mkdir -p /data && chown cloudcli:cloudcli /data

COPY docker/railway/entrypoint.sh /usr/local/bin/cloudcli-entrypoint
RUN chmod +x /usr/local/bin/cloudcli-entrypoint

ENV HOME=/data \
    DATABASE_PATH=/data/.cloudcli/auth.db \
    HOST=0.0.0.0 \
    SERVER_PORT=3001

EXPOSE 3001
ENTRYPOINT ["cloudcli-entrypoint"]
CMD ["node", "dist-server/server/index.js"]
