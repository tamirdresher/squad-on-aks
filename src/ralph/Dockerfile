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

# Copilot CLI extension (runs autonomous Copilot sessions)
# Install as root, then make available to ralph user
RUN gh extension install github/gh-copilot 2>/dev/null || true

# Optional: Agency CLI binary (copy pre-built binary if available)
# To use: place agency-linux binary in build context, uncomment:
# COPY agency-linux /usr/local/bin/agency
# RUN chmod +x /usr/local/bin/agency

# Non-root user
RUN useradd -m -s /bin/bash ralph
ENV HOME=/home/ralph
RUN mkdir -p /home/ralph/.local/share/gh/extensions && \
    chown -R ralph:ralph /home/ralph
# Copy gh extensions to ralph user
RUN cp -r /root/.local/share/gh/extensions/* /home/ralph/.local/share/gh/extensions/ 2>/dev/null || true && \
    chown -R ralph:ralph /home/ralph/.local/share/gh/extensions

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
