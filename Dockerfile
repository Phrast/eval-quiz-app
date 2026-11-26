# Étape 1 : construction du site avec Vite
FROM node:22.23.5-alpine3.24 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# Étape 2 : nginx officiel 1.30.8 (failles de la 1.30.6 corrigées), exécuté sans root
FROM nginx:1.30.8-alpine3.24
RUN apk upgrade --no-cache \
 && sed -i -e '/^user /d' -e 's#^pid .*#pid /tmp/nginx.pid;#' /etc/nginx/nginx.conf \
 && chown -R nginx:nginx /var/cache/nginx /etc/nginx/conf.d
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
USER nginx
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/ >/dev/null || exit 1
