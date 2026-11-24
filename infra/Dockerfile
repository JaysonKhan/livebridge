# LiveBridge gateway. Build from the repository root:  docker build -f infra/Dockerfile -t livebridge-gateway .
# Node 24 LTS runs the TypeScript sources directly (type stripping), so there is no build step.
FROM node:24-alpine
WORKDIR /app
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8201
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund
COPY packages/protocol/src packages/protocol/src
COPY services/gateway/src services/gateway/src
USER node
EXPOSE 8201
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8201/healthz').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"
CMD ["node", "services/gateway/src/main.ts"]
