# J0 — Vérification des abonnements Azure

**Date :** 26/11/2026 (identifiants masqués)

## Résultats

| Vérification | Abonnement du projet (Mathis) | Abonnement de secours (Nicolas) |
|---|---|---|
| Abonnement | Azure for Students, `Enabled` | Azure for Students, `Enabled` |
| Rôle | Owner | Owner |
| Crédits restants | 100 $ | 100 $ |
| Fournisseurs `Microsoft.App`, `OperationalInsights`, `ContainerRegistry`, `ManagedIdentity` | `Registered` | `Registered` |
| Régions autorisées | italynorth, spaincentral, belgiumcentral, norwayeast, denmarkeast | italynorth, spaincentral, belgiumcentral, germanywestcentral, denmarkeast |
| Régions utilisables (ACR + Container Apps disponibles) | italynorth, spaincentral, belgiumcentral, norwayeast | italynorth, spaincentral, belgiumcentral, germanywestcentral |

## Restrictions constatées

- Azure impose **5 régions par abonnement étudiant** (règle « Allowed resource deployment regions »), et la liste diffère selon le compte.
- **France Central est refusée** sur les deux abonnements (`RequestDisallowedByAzure`).
- **Denmark East** est autorisée, mais Azure Container Apps n'y est pas disponible.

## Décision

- **Abonnement :** celui de Mathis. Celui de Nicolas reste en secours.
- **Région : `italynorth`**, autorisée et utilisable sur les deux abonnements.

## Commandes utilisées

```bash
az account show -o table
az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)" --all -o table
for ns in Microsoft.App Microsoft.OperationalInsights Microsoft.ContainerRegistry Microsoft.ManagedIdentity; do
  az provider register --namespace $ns --wait
  az provider show -n $ns --query registrationState -o tsv
done
az policy assignment list --disable-scope-strict-match \
  --query "[?parameters.listOfAllowedLocations].{nom:displayName, regions:parameters.listOfAllowedLocations.value}" -o json
az provider show -n Microsoft.App --query "resourceTypes[?resourceType=='managedEnvironments'].locations[]" -o tsv
az provider show -n Microsoft.ContainerRegistry --query "resourceTypes[?resourceType=='registries'].locations[]" -o tsv

# Test de France Central, puis nettoyage
az group create -n rg-test-region -l francecentral
az identity create -n id-test-region -g rg-test-region -l francecentral   # → RequestDisallowedByAzure
az group delete -n rg-test-region --yes --no-wait
```
