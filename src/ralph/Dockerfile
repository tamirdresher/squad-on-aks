# Squad Ralph — Persistent work queue monitor
# Watches GitHub/ADO for new issues and keeps agents alive

FROM node:20-slim AS base
WORKDIR /app

RUN apt-get update && apt-get install -y curl && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
RUN npm ci --production

COPY . .

ENV NODE_ENV=production
ENV SQUAD_ROLE=ralph

# Ralph runs as a long-lived process — no port needed
CMD ["node", "src/index.js"]
