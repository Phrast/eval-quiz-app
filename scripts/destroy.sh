#!/usr/bin/env bash
# scripts/destroy.sh — Supprime TOUTES les ressources Azure de Quiz App en supprimant le groupe :
# ACR (et ses images), environnement, Container Apps, identités managées, Log Analytics.
# À lancer uniquement APRÈS sauvegarde des preuves et avec l'accord du formateur.
# La base Neon n'est pas concernée : elle se supprime depuis la console Neon.
# Après suppression : retirer les secrets AZURE_* de GitHub (l'identité n'existe plus).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

if [ "$(az group exists -n "$RG")" != "true" ]; then
  echo "Le groupe $RG n'existe pas : rien à supprimer."; exit 0
fi

echo "Ressources qui seront supprimées :"
az resource list -g "$RG" --query '[].{nom:name, type:type}' -o table

read -r -p "Supprimer TOUT le groupe $RG ? Tapez son nom pour confirmer : " c   # garde-fou
[ "$c" = "$RG" ] || { echo "Annulé"; exit 1; }

az group delete -n "$RG" --yes --no-wait
echo "Suppression lancée — vérifier avec : az group exists -n $RG   (false attendu)"
