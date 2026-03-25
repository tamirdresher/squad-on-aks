FROM mcr.microsoft.com/powershell:latest AS runtime

LABEL maintainer="squad-team" \
      description="Ralph — Squad Work Monitor agent for K8s" \
      org.opencontainers.image.source="https://github.com/tamirdresher/squad-on-aks"

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git ca-certificates gnupg jq \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20 LTS (required for Copilot CLI / agency)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Agency CLI (runs Copilot sessions)
RUN curl -fsSL https://aka.ms/PathInstaller-linux-x64 -o /tmp/pathinstaller.tar.gz \
    && mkdir -p /tmp/pathinstaller \
    && tar -xzf /tmp/pathinstaller.tar.gz -C /tmp/pathinstaller \
    && chmod +x /tmp/pathinstaller/PathInstaller \
    && /tmp/pathinstaller/PathInstaller Install Agency \
    && rm -rf /tmp/pathinstaller /tmp/pathinstaller.tar.gz \
    && AGENCY_BIN=$(find / -name "agency" -type f -executable 2>/dev/null | head -1) \
    && if [ -n "$AGENCY_BIN" ]; then ln -sf "$AGENCY_BIN" /usr/local/bin/agency; fi

# Non-root user
RUN useradd -m -s /bin/bash ralph
ENV HOME=/home/ralph
RUN mkdir -p /home/ralph/.agency /home/ralph/.local/share/gh/extensions && \
    chown -R ralph:ralph /home/ralph

WORKDIR /app

# Copy Squad config and entrypoint
COPY squad.config.ts ./
COPY ralph-k8s-entrypoint.ps1 ./

ENV GH_TOKEN="" \
    GITHUB_REPOSITORY="" \
    RALPH_INTERVAL_SECONDS="300" \
    RALPH_LOG_LEVEL="info" \
    SQUAD_CONFIG_PATH="/app/squad.config.ts"

USER ralph

HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD ["pwsh", "-NoProfile", "-Command", "if ($PSVersionTable.PSVersion.Major -ge 7) { exit 0 } else { exit 1 }"]

ENTRYPOINT ["pwsh", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "/app/ralph-k8s-entrypoint.ps1"]
