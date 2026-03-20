# Squad Agent Base Image
# All specialized agents (data, worf, seven, etc.) extend this

FROM node:20-slim AS base
WORKDIR /app

RUN apt-get update && apt-get install -y curl git && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Common agent dependencies
COPY package*.json ./
RUN npm ci --production

COPY . .

ENV NODE_ENV=production
ENV SQUAD_ROLE=agent

# Agents are ephemeral — they process a task and exit
CMD ["node", "src/index.js"]
