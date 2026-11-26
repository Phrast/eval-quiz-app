# Étape 1 : dépendances de production uniquement
FROM node:22.23.5-alpine3.24 AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Étape 2 : image d'exécution minimale
FROM node:22.23.5-alpine3.24
ENV NODE_ENV=production
# Correctifs système, tini (PID 1), suppression de npm/yarn/corepack inutiles à l'exécution
RUN apk upgrade --no-cache \
 && apk add --no-cache tini \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
           /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json server.js ./
USER node
EXPOSE 3007
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:3007/health || exit 1
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "server.js"]
