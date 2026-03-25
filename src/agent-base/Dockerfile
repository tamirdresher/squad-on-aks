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

RUN curl -fsSL https://aka.ms/PathInstaller-linux-x64 -o /tmp/pathinstaller.tar.gz \
    && mkdir -p /tmp/pathinstaller \
    && tar -xzf /tmp/pathinstaller.tar.gz -C /tmp/pathinstaller \
    && chmod +x /tmp/pathinstaller/PathInstaller \
    && /tmp/pathinstaller/PathInstaller Install Agency \
    && rm -rf /tmp/pathinstaller /tmp/pathinstaller.tar.gz \
    && AGENCY_BIN=$(find / -name "agency" -type f -executable 2>/dev/null | head -1) \
    && if [ -n "$AGENCY_BIN" ]; then ln -sf "$AGENCY_BIN" /usr/local/bin/agency; fi

RUN useradd -m -s /bin/bash agent
ENV HOME=/home/agent
RUN mkdir -p /home/agent/.agency /home/agent/.local/share/gh/extensions && \
    chown -R agent:agent /home/agent

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
