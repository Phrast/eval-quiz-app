#!/usr/bin/env bash
# scripts/setup-github-oidc.sh — Identité utilisée par le workflow CD (GitHub Actions) pour se connecter à Azure
# en OIDC : aucun mot de passe ni secret client à stocker dans GitHub.
# Identité managée plutôt qu'app registration : pas besoin de droits Entra ID (souvent refusés aux étudiants).
# Droits minimaux : AcrPush sur CET ACR + Contributor sur CE groupe (pour az containerapp update).
#
# À lancer une fois par M2 (Owner de l'abonnement), APRÈS un premier bash scripts/deploy.sh.
# Ré-exécutable sans erreur. Les 3 identifiants affichés à la fin sont à transmettre à M1 en privé.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

CI_ID_NAME="id-quiz-github"
GITHUB_SUBJECT="repo:Phrast/eval-quiz-app:ref:refs/heads/main"   # casse exacte : seule la branche main peut obtenir un jeton

az identity show -n "$CI_ID_NAME" -g "$RG" -o none 2>/dev/null || \
  az identity create -n "$CI_ID_NAME" -g "$RG" -o none
CLIENT_ID=$(az identity show -n "$CI_ID_NAME" -g "$RG" --query clientId -o tsv)
PRINCIPAL=$(az identity show -n "$CI_ID_NAME" -g "$RG" --query principalId -o tsv)

az identity federated-credential show --name github-main --identity-name "$CI_ID_NAME" -g "$RG" -o none 2>/dev/null || \
  az identity federated-credential create --name github-main --identity-name "$CI_ID_NAME" -g "$RG" \
    --issuer https://token.actions.githubusercontent.com \
    --subject "$GITHUB_SUBJECT" \
    --audiences api://AzureADTokenExchange -o none

ACR_ID=$(az acr show -n "$ACR_NAME" --query id -o tsv)
RG_ID=$(az group show -n "$RG" --query id -o tsv)
assign() {   # assign <rôle> <portée> : crée l'attribution seulement si elle n'existe pas
  if [ "$(az role assignment list --assignee "$PRINCIPAL" --role "$1" --scope "$2" --query 'length(@)' -o tsv)" = "0" ]; then
    az role assignment create --assignee-object-id "$PRINCIPAL" --assignee-principal-type ServicePrincipal \
      --role "$1" --scope "$2" -o none
  fi
}
assign AcrPush "$ACR_ID"        # pousser des images, sur cet ACR seulement
assign Contributor "$RG_ID"     # mettre à jour les Container Apps, sur ce groupe seulement

echo
echo "À transmettre à M1 EN PRIVÉ (GitHub > Settings > Secrets and variables > Actions) :"
echo "  Secrets   : AZURE_CLIENT_ID=$CLIENT_ID"
az account show --query "{AZURE_TENANT_ID:tenantId, AZURE_SUBSCRIPTION_ID:id}" -o json
echo "  Variables : ACR_NAME=$ACR_NAME  RESOURCE_GROUP=$RG  BACKEND_APP=$BACKEND_APP  FRONTEND_APP=$FRONTEND_APP"
echo "Ne pas faire apparaître ces identifiants dans les preuves."
