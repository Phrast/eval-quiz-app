# scripts/config.sh — Paramètres Azure NON sensibles, partagés par deploy.sh, destroy.sh et setup-github-oidc.sh.
# Versionné : ne JAMAIS mettre de secret ici (les secrets sont dans .env.azure, ignoré par git).

RG="rg-quiz-app"                                   # groupe de ressources : le supprimer supprime tout
LOCATION="italynorth"                              # région validée en J0 (autorisée sur les deux abonnements)
ACR_NAME="acrquizmb2611"                           # unique au monde, minuscules et chiffres uniquement (5-50 car.)
ENV_NAME="cae-quiz"                                # environnement Azure Container Apps
BACKEND_APP="quiz-backend"                         # nom = nom DNS interne utilisé par nginx (http://quiz-backend)
FRONTEND_APP="quiz-frontend"
PULL_IDENTITY="id-quiz-acrpull"                    # identité managée qui tire les images (rôle AcrPull)
MIN_REPLICAS="${MIN_REPLICAS:-0}"                  # 0 = scale-to-zero (économie) ; MIN_REPLICAS=1 le jour de la démo
TAG="${TAG:-$(git rev-parse --short=7 HEAD)}"      # tag = SHA court du commit, sauf si TAG est déjà défini
