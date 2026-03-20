# Squad Coordinator Container
# Routes issues to agents, orchestrates multi-agent collaboration

FROM node:20-slim AS base
WORKDIR /app

# Install GitHub CLI
RUN apt-get update && apt-get install -y curl && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Copilot CLI (placeholder — depends on distribution method)
# RUN npm install -g @github/copilot-cli

COPY package*.json ./
RUN npm ci --production

COPY . .

ENV NODE_ENV=production
ENV SQUAD_ROLE=coordinator

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

CMD ["node", "src/index.js"]
