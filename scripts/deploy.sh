#!/usr/bin/env bash
# scripts/deploy.sh — Crée (si absentes) puis met à jour les ressources Azure de Quiz App :
#   groupe de ressources -> ACR -> images taguées par SHA -> environnement ACA
#   -> identité AcrPull -> backend (ingress interne, 3007) -> frontend (ingress externe, 8080).
# Idempotent : on peut le relancer autant de fois que nécessaire.
#
# Prérequis : terminal WSL/Linux, az login fait, Docker démarré, scripts/config.sh rempli,
#             .env.azure rempli (copie de .env.azure.example), Dockerfiles de M1 présents.
# Usage     : bash scripts/deploy.sh          (MIN_REPLICAS=1 bash scripts/deploy.sh le jour de la démo)
# Ne jamais ajouter "set -x" : les secrets s'afficheraient dans le terminal.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh
[ -f .env.azure ] || { echo "Fichier .env.azure absent : cp .env.azure.example .env.azure puis le remplir"; exit 1; }
set -a; source .env.azure; set +a
: "${DATABASE_URL:?}" "${JWT_SECRET:?}" "${ADMIN_PASSWORD:?}" "${RESEND_API_KEY:?}" "${ADMIN_USERNAME:?}" "${FROM_EMAIL:?}"

log() { printf '\n==> %s\n' "$*"; }

# ---------------------------------------------------------------- Partie 1 : ACR (J3)
log "Extension containerapp"
az extension add --name containerapp --upgrade --only-show-errors

log "Groupe de ressources $RG ($LOCATION)"
az group create -n "$RG" -l "$LOCATION" -o none

log "Registre $ACR_NAME (Basic, compte admin désactivé)"
az acr show -n "$ACR_NAME" -g "$RG" -o none 2>/dev/null || \
  az acr create -n "$ACR_NAME" -g "$RG" --sku Basic --admin-enabled false -o none
ACR_SERVER=$(az acr show -n "$ACR_NAME" --query loginServer -o tsv)
ACR_ID=$(az acr show -n "$ACR_NAME" --query id -o tsv)

log "Build local et push des images (tag $TAG)"
# Build local : ACR Tasks (az acr build) est souvent refusé sur les abonnements étudiants.
az acr login -n "$ACR_NAME"
docker build -t "$ACR_SERVER/quiz-backend:$TAG"  ./backend
docker build -t "$ACR_SERVER/quiz-frontend:$TAG" .
docker push "$ACR_SERVER/quiz-backend:$TAG"
docker push "$ACR_SERVER/quiz-frontend:$TAG"

# ---------------------------------------------------------------- Partie 2 : Container Apps (J4)
log "Environnement Container Apps $ENV_NAME"
az containerapp env show -n "$ENV_NAME" -g "$RG" -o none 2>/dev/null || \
  az containerapp env create -n "$ENV_NAME" -g "$RG" -l "$LOCATION" -o none

log "Identité managée $PULL_IDENTITY (AcrPull sur $ACR_NAME uniquement)"
az identity show -n "$PULL_IDENTITY" -g "$RG" -o none 2>/dev/null || \
  az identity create -n "$PULL_IDENTITY" -g "$RG" -o none
PULL_ID=$(az identity show -n "$PULL_IDENTITY" -g "$RG" --query id -o tsv)
PULL_PRINCIPAL=$(az identity show -n "$PULL_IDENTITY" -g "$RG" --query principalId -o tsv)
if [ "$(az role assignment list --assignee "$PULL_PRINCIPAL" --scope "$ACR_ID" --role AcrPull --query 'length(@)' -o tsv)" = "0" ]; then
  az role assignment create --assignee-object-id "$PULL_PRINCIPAL" --assignee-principal-type ServicePrincipal \
    --role AcrPull --scope "$ACR_ID" -o none
  echo "Attente de la propagation du rôle (60 s)..."
  sleep 60
fi

# Secrets ACA (chiffrés dans l'app) ; les variables les référencent par secretref:
SECRETS=(database-url="$DATABASE_URL" jwt-secret="$JWT_SECRET" admin-password="$ADMIN_PASSWORD" resend-api-key="$RESEND_API_KEY")

log "Backend $BACKEND_APP (ingress interne, port 3007)"
if az containerapp show -n "$BACKEND_APP" -g "$RG" -o none 2>/dev/null; then
  az containerapp secret set -n "$BACKEND_APP" -g "$RG" --secrets "${SECRETS[@]}" -o none
  az containerapp update -n "$BACKEND_APP" -g "$RG" --image "$ACR_SERVER/quiz-backend:$TAG" \
    --min-replicas "$MIN_REPLICAS" -o none
else
  az containerapp create -n "$BACKEND_APP" -g "$RG" --environment "$ENV_NAME" \
    --image "$ACR_SERVER/quiz-backend:$TAG" \
    --registry-server "$ACR_SERVER" --registry-identity "$PULL_ID" --user-assigned "$PULL_ID" \
    --ingress internal --target-port 3007 \
    --cpu 0.25 --memory 0.5Gi --min-replicas "$MIN_REPLICAS" --max-replicas 1 \
    --secrets "${SECRETS[@]}" \
    --env-vars DATABASE_URL=secretref:database-url JWT_SECRET=secretref:jwt-secret \
               ADMIN_USERNAME="$ADMIN_USERNAME" ADMIN_PASSWORD=secretref:admin-password \
               RESEND_API_KEY=secretref:resend-api-key FROM_EMAIL="$FROM_EMAIL" -o none
  # nginx parle au backend en HTTP dans l'environnement : sans ceci, l'ingress répond 301 (redirection HTTPS)
  az containerapp ingress update -n "$BACKEND_APP" -g "$RG" --allow-insecure -o none
fi

log "Frontend $FRONTEND_APP (ingress externe, port 8080)"
# Le backend doit exister avant : nginx résout http://quiz-backend au démarrage.
if az containerapp show -n "$FRONTEND_APP" -g "$RG" -o none 2>/dev/null; then
  az containerapp update -n "$FRONTEND_APP" -g "$RG" --image "$ACR_SERVER/quiz-frontend:$TAG" \
    --min-replicas "$MIN_REPLICAS" -o none
else
  az containerapp create -n "$FRONTEND_APP" -g "$RG" --environment "$ENV_NAME" \
    --image "$ACR_SERVER/quiz-frontend:$TAG" \
    --registry-server "$ACR_SERVER" --registry-identity "$PULL_ID" --user-assigned "$PULL_ID" \
    --ingress external --target-port 8080 \
    --cpu 0.25 --memory 0.5Gi --min-replicas "$MIN_REPLICAS" --max-replicas 1 \
    --env-vars BACKEND_URL="http://$BACKEND_APP" -o none
fi

FQDN=$(az containerapp show -n "$FRONTEND_APP" -g "$RG" --query properties.configuration.ingress.fqdn -o tsv)
log "Déploiement terminé (tag $TAG)"
echo "Frontend : https://$FQDN"
echo "Santé    : curl -i https://$FQDN/health"
