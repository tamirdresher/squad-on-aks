# Squad Ralph Agent — Multi-stage Docker Build
# Runs the Ralph work monitor with Agency CLI (Copilot-powered AI agent)
#
# Build:
#   az acr build --registry <acr> --image squad-ralph:latest --file docker/Dockerfile .
#   OR: docker build -f docker/Dockerfile -t squad-ralph:latest .

FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

# Install Node.js 20, gh CLI, and common tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git jq unzip \
  && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y nodejs \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
     | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
     | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && apt-get update && apt-get install -y gh \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Agency CLI (GitHub Copilot CLI for headless agent execution)
# Users can override AGENCY_VERSION to pin a specific version
ARG AGENCY_VERSION=latest
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$AGENCY_VERSION" = "latest" ]; then \
      DOWNLOAD_URL=$(curl -s https://api.github.com/repos/github/copilot-cli/releases/latest \
        | jq -r ".assets[] | select(.name | contains(\"linux\") and contains(\"$ARCH\")) | .browser_download_url" \
        | head -1); \
    else \
      DOWNLOAD_URL="https://github.com/github/copilot-cli/releases/download/$AGENCY_VERSION/agency-linux-$ARCH"; \
    fi && \
    if [ -n "$DOWNLOAD_URL" ] && [ "$DOWNLOAD_URL" != "null" ]; then \
      curl -L -o /usr/local/bin/agency "$DOWNLOAD_URL" && \
      chmod +x /usr/local/bin/agency && \
      echo "Agency CLI installed from $DOWNLOAD_URL"; \
    else \
      echo "WARNING: Agency CLI not available for this architecture. Falling back to gh copilot."; \
    fi

WORKDIR /app

# Copy Squad team config (used by agents for context)
COPY .squad/team.md .squad/routing.md ./.squad/

# Copy scripts
COPY scripts/ralph-watch.ps1 ./ralph-watch.ps1
COPY scripts/ralph-k8s-entrypoint.ps1 ./ralph-k8s-entrypoint.ps1

# Environment defaults (override via K8s env or secrets)
ENV SQUAD_AGENT_TYPE=ralph
ENV NODE_ENV=production

# Health check
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD pwsh -Command "Get-Process -Name pwsh -ErrorAction SilentlyContinue" || exit 1

# Entry point: run the Agency-powered Ralph
ENTRYPOINT ["pwsh", "-File", "./ralph-k8s-entrypoint.ps1"]
