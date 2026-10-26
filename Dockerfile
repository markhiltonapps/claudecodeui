# Production image for CloudCLI UI (Claude Code UI) on Railway or any Docker host.
# Stage 1 compiles the native modules and builds the client + server.
# Stage 2 is the runtime image: no compiler toolchain, just the built app,
# the Claude Code CLI, and the everyday tools the agent and shell expect.

# ---------------------------------------------------------------- build stage
FROM node:22-bookworm-slim AS build

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    ELECTRON_SKIP_BINARY_DOWNLOAD=1 \
    HUSKY=0 \
    CI=true

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential python3 python3-setuptools ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./
COPY scripts ./scripts
# Install with lifecycle scripts off: @vscode/ripgrep's postinstall downloads
# a binary through the GitHub API, which rate-limits shared build hosts. The
# native modules are rebuilt explicitly; ripgrep is linked to the apt binary
# in the runtime stage.
RUN npm ci --include=dev --ignore-scripts --no-audit --no-fund \
    && npm rebuild node-pty better-sqlite3 bcrypt --no-audit --no-fund

COPY . .
RUN npm run build && npm prune --omit=dev --no-audit --no-fund

# -------------------------------------------------------------- runtime stage
FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates openssh-client \
      ripgrep jq sqlite3 zip unzip tree vim-tiny less procps gosu \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI (the UI spawns it for every Claude session).
RUN npm install -g @anthropic-ai/claude-code --no-audit --no-fund

WORKDIR /app
COPY --from=build /app /app
RUN mkdir -p node_modules/@vscode/ripgrep/bin \
    && ln -sf "$(command -v rg)" node_modules/@vscode/ripgrep/bin/rg

# Non-root runtime user whose home IS the volume, so ~/.claude (login,
# sessions), ~/.cloudcli (auth.db) and every project survive redeploys.
RUN mkdir -p /data \
    && groupadd -r cloudcli \
    && useradd -r -g cloudcli -d /data -s /bin/bash cloudcli \
    && chown -R cloudcli:cloudcli /data /app

COPY docker/railway/entrypoint.sh /usr/local/bin/cloudcli-entrypoint
RUN chmod +x /usr/local/bin/cloudcli-entrypoint

ENV HOME=/data \
    WORKSPACES_ROOT=/data \
    DATABASE_PATH=/data/.cloudcli/auth.db \
    HOST=0.0.0.0 \
    PORT=3001 \
    SERVER_PORT=3001

EXPOSE 3001
ENTRYPOINT ["cloudcli-entrypoint"]
CMD ["node", "dist-server/server/index.js"]
