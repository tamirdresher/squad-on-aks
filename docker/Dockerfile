# Squad Ralph Agent — Multi-stage Docker Build
# Runs the Ralph work monitor (GitHub issue poller + dispatcher)

# Stage 1: Node.js dependencies
FROM node:20-slim AS node-deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev 2>/dev/null || npm install --omit=dev

# Stage 2: Runtime
FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

# Install Node.js 20 and gh CLI
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git jq \
  && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y nodejs \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
     | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
     | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && apt-get update && apt-get install -y gh \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Node.js deps from stage 1
COPY --from=node-deps /app/node_modules ./node_modules

# Copy application files
COPY squad.config.ts ./
COPY scripts/ralph-watch.ps1 ./
COPY .squad/team.md .squad/routing.md ./.squad/

# Environment defaults (override via K8s env or secrets)
ENV SQUAD_AGENT_TYPE=ralph
ENV NODE_ENV=production

# Health check — Ralph exits on its own, so this is for long-running agents
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD pwsh -Command "Get-Process -Name pwsh -ErrorAction SilentlyContinue" || exit 1

# Entry point: run the Ralph watch loop
ENTRYPOINT ["pwsh", "-File", "./ralph-watch.ps1"]
