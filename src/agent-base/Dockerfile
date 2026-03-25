FROM mcr.microsoft.com/powershell:latest

LABEL maintainer="squad-team" \
      description="Squad Agent — Copilot-powered AI agent worker" \
      org.opencontainers.image.source="https://github.com/tamirdresher/squad-on-aks"

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git ca-certificates gnupg jq \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Copilot CLI extension
RUN gh extension install github/gh-copilot 2>/dev/null || true

# Optional: Agency CLI binary (copy pre-built binary if available)
# COPY agency-linux /usr/local/bin/agency
# RUN chmod +x /usr/local/bin/agency

RUN useradd -m -s /bin/bash agent
ENV HOME=/home/agent
RUN mkdir -p /home/agent/.local/share/gh/extensions && \
    chown -R agent:agent /home/agent
RUN cp -r /root/.local/share/gh/extensions/* /home/agent/.local/share/gh/extensions/ 2>/dev/null || true && \
    chown -R agent:agent /home/agent/.local/share/gh/extensions

WORKDIR /app

COPY squad.config.ts ./
COPY agent-entrypoint.ps1 ./

ENV GH_TOKEN="" \
    GITHUB_REPOSITORY="" \
    SQUAD_AGENT_TYPE="picard" \
    SQUAD_MODEL="claude-sonnet-4.5" \
    SQUAD_CONFIG_PATH="/app/squad.config.ts"

USER agent

HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD ["pwsh", "-NoProfile", "-Command", "Test-Path /tmp/agent-ready"]

ENTRYPOINT ["pwsh", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "/app/agent-entrypoint.ps1"]
