# J0 — Vérification des abonnements Azure

Objectif (doc 03, J0) : vérifier que l'abonnement fonctionne et identifier les restrictions (ACR, Azure Container Apps, région, quotas, crédits) **avant** de créer des ressources payantes.

Les identifiants (abonnement, tenant, compte étudiant) et le code de connexion sont masqués volontairement.

---

## Abonnement de Nicolas (secours)

**Date :** 26/11/2026
**Rôle dans le projet :** abonnement de secours, si les crédits de l'abonnement du projet s'épuisent (`deploy.sh` permet de tout recréer ailleurs).

### 1. Connexion et abonnement actif

```console
$ az login --use-device-code
(connexion via le navigateur, code de connexion masqué)
[1] *  Azure for Students   <id-abonnement masqué>   <tenant de l'école>

$ az account show -o table   (extrait, identifiants masqués)
EnvironmentName    IsDefault    Name                State
-----------------  -----------  ------------------  -------
AzureCloud         True         Azure for Students  Enabled
```

**Résultat :** abonnement « Azure for Students » actif (`Enabled`) et sélectionné par défaut.

### 2. Fournisseurs de ressources

```console
$ for ns in Microsoft.App Microsoft.OperationalInsights Microsoft.ContainerRegistry Microsoft.ManagedIdentity; do
    az provider register --namespace $ns --wait
  done
```

**Résultat :** commande terminée sans erreur. `--wait` attend la fin de chaque enregistrement, et la commande n'affiche rien quand tout se passe bien.

⚠️ À compléter : lancer la vérification ci-dessous et coller sa sortie (les 4 doivent être `Registered`) :

```console
$ for ns in Microsoft.App Microsoft.OperationalInsights Microsoft.ContainerRegistry Microsoft.ManagedIdentity; do
    printf '%-32s %s\n' "$ns" "$(az provider show -n $ns --query registrationState -o tsv)"; done
```

### 3. Rôle sur l'abonnement

```console
$ az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)" --all -o table
Principal              Role    Scope
---------------------  ------  ------------------------------------
<compte étudiant>      Owner   /subscriptions/<id-abonnement masqué>
```

**Résultat :** rôle **Owner** sur l'abonnement. Il est nécessaire pour attribuer des rôles plus tard (AcrPull pour les Container Apps, AcrPush et Contributor pour la CI/CD).

### 4. Crédits restants

⚠️ À compléter : montant des crédits restants et date (portail Azure → *Education* ou *Cost Management*).

### 5. Région : test de France Central

```console
$ az group create -n rg-test-region -l francecentral
{
  "id": "/subscriptions/<id-abonnement masqué>/resourceGroups/rg-test-region",
  "location": "francecentral",
  "name": "rg-test-region",
  "properties": { "provisioningState": "Succeeded" },
  ...
}

$ az identity create -n id-test-region -g rg-test-region -l francecentral -o none
(RequestDisallowedByAzure) Resource 'id-test-region' was disallowed by Azure: This policy maintains a set of
best available regions where your subscription can deploy resources. [...]
Code: RequestDisallowedByAzure
```

**Résultat :** la création d'un **groupe de ressources** en `francecentral` passe, mais pas celle d'une **ressource**. Une identité managée gratuite a servi de test. France Central est donc **inutilisable** pour le projet.

### 6. Régions autorisées

```console
$ az policy assignment list --disable-scope-strict-match \
    --query "[?parameters.listOfAllowedLocations].{nom:displayName, regions:parameters.listOfAllowedLocations.value}" -o json
[
  {
    "nom": "Allowed resource deployment regions",
    "regions": [ "italynorth", "denmarkeast", "germanywestcentral", "belgiumcentral", "spaincentral" ]
  }
]
```

### 7. Disponibilité des services dans ces régions

```console
$ az provider show -n Microsoft.App --query "resourceTypes[?resourceType=='managedEnvironments'].locations[]" -o tsv | grep -iE "germany|italy|spain|denmark|belgium"
Germany West Central
Germany North
Belgium Central
Spain Central
Italy North

$ az provider show -n Microsoft.ContainerRegistry --query "resourceTypes[?resourceType=='registries'].locations[]" -o tsv | grep -iE "germany|italy|spain|denmark|belgium"
Germany West Central
Germany North
Italy North
Spain Central
Belgium Central
Denmark East
```

`Germany North` apparaît à cause du filtre `grep`, mais ne fait pas partie des régions autorisées.

| Région | Autorisée | Azure Container Apps | ACR | Utilisable |
|---|---|---|---|---|
| `germanywestcentral` | ✔ | ✔ | ✔ | ✔ |
| `italynorth` | ✔ | ✔ | ✔ | ✔ |
| `spaincentral` | ✔ | ✔ | ✔ | ✔ |
| `belgiumcentral` | ✔ | ✔ | ✔ | ✔ |
| `denmarkeast` | ✔ | ✘ | ✔ | ✘ (pas de Container Apps) |

### 8. Nettoyage

```console
$ az group delete -n rg-test-region --yes --no-wait
```

Le groupe de test est supprimé avec son contenu. Aucune ressource payante n'a été créée.

### Restrictions constatées

- **Région** : l'abonnement n'autorise que 5 régions (règle « Allowed resource deployment regions » imposée par Azure). France Central est refusée (`RequestDisallowedByAzure`).
- **Denmark East** : autorisée, mais Azure Container Apps n'y est pas disponible.

### Région proposée

**`germanywestcentral`** (Francfort) : autorisée, Container Apps et ACR disponibles, région mature et proche de Neon (Francfort) pour la base PostgreSQL cloud (J5). À confirmer avec l'abonnement du projet ci-dessous.

---

## Abonnement de Mathis (projet)

**Date :** 26/11/2026
**Rôle dans le projet :** abonnement principal. Il héberge l'ACR, l'environnement Container Apps, les deux applications et les identités managées.

### 1. Connexion et abonnement actif

```console
$ az login --use-device-code
(connexion via le navigateur, code de connexion masqué)

$ az account show --query "{name:name, state:state, isDefault:isDefault}" -o table
Name                State    IsDefault
------------------  -------  -----------
Azure for Students  Enabled  True
```

**Résultat :** l'abonnement « Azure for Students » est actif (`Enabled`) et sélectionné par défaut.

### 2. Fournisseurs de ressources

```console
$ for ns in Microsoft.App Microsoft.OperationalInsights Microsoft.ContainerRegistry Microsoft.ManagedIdentity; do
    az provider register --namespace $ns --wait
  done

$ for ns in Microsoft.App Microsoft.OperationalInsights Microsoft.ContainerRegistry Microsoft.ManagedIdentity; do
    printf '%-32s %s\n' "$ns" "$(az provider show -n $ns --query registrationState -o tsv)"; done
Microsoft.App                    Registered
Microsoft.OperationalInsights    Registered
Microsoft.ContainerRegistry      Registered
Microsoft.ManagedIdentity        Registered
```

**Résultat :** les 4 fournisseurs sont enregistrés (`Registered`).

### 3. Rôle sur l'abonnement

```console
$ az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)" --all \
    --query "[].{role:roleDefinitionName, scope:scope}" -o table
Role    Scope
------  ------------------------------------
Owner   /subscriptions/<id-abonnement masqué>
```

**Résultat :** rôle **Owner** sur l'abonnement. Il permet d'attribuer AcrPull (Container Apps), puis AcrPush et Contributor (identité OIDC de la CD).

### 4. Crédits restants

**Crédits restants au 26/11/2026 : 100 $** (portail Azure → *Education*). Le crédit est entier : aucune ressource payante n'a encore été créée.

### 5. Région : test de France Central

```console
$ az group create -n rg-test-region -l francecentral
(groupe créé : "provisioningState": "Succeeded")

$ az identity create -n id-test-region -g rg-test-region -l francecentral -o none
ERROR: (RequestDisallowedByAzure) Resource 'id-test-region' was disallowed by Azure: This policy maintains a set of
best available regions where your subscription can deploy resources. [...]
Code: RequestDisallowedByAzure
```

**Résultat :** on obtient le même comportement que sur l'abonnement de secours. Le groupe est accepté, mais la ressource est refusée. France Central est donc **inutilisable**.

### 6. Régions autorisées

```console
$ az policy assignment list --disable-scope-strict-match \
    --query "[?parameters.listOfAllowedLocations].{nom:displayName, regions:parameters.listOfAllowedLocations.value}" -o json
[
  {
    "nom": "Allowed resource deployment regions",
    "regions": [ "belgiumcentral", "denmarkeast", "italynorth", "spaincentral", "norwayeast" ]
  }
]
```

⚠️ **La liste diffère de celle de l'abonnement de secours.** `germanywestcentral` n'y figure **pas**, et `norwayeast` remplace cette région.

### 7. Disponibilité des services dans ces régions

```console
$ az provider show -n Microsoft.App --query "resourceTypes[?resourceType=='managedEnvironments'].locations[]" -o tsv | grep -iE "belgium|denmark|italy|spain|norway"
Norway East
Belgium Central
Spain Central
Italy North

$ az provider show -n Microsoft.ContainerRegistry --query "resourceTypes[?resourceType=='registries'].locations[]" -o tsv | grep -iE "belgium|denmark|italy|spain|norway"
Norway East
Norway West
Italy North
Spain Central
Belgium Central
Denmark East

$ az provider show -n Microsoft.OperationalInsights --query "resourceTypes[?resourceType=='workspaces'].locations[]" -o tsv | grep -iE "belgium|denmark|italy|spain|norway"
Norway East
Norway West
Italy North
Spain Central
Denmark East
Belgium Central
```

`Norway West` apparaît à cause du filtre `grep`, mais ne fait pas partie des régions autorisées.

| Région | Autorisée | Azure Container Apps | ACR | Log Analytics | Utilisable |
|---|---|---|---|---|---|
| `italynorth` | ✔ | ✔ | ✔ | ✔ | ✔ |
| `spaincentral` | ✔ | ✔ | ✔ | ✔ | ✔ |
| `belgiumcentral` | ✔ | ✔ | ✔ | ✔ | ✔ |
| `norwayeast` | ✔ | ✔ | ✔ | ✔ | ✔ |
| `denmarkeast` | ✔ | ✘ | ✔ | ✔ | ✘ (pas de Container Apps) |

### 8. Nettoyage

```console
$ az resource list -g rg-test-region -o table
(aucune ressource : l'identité de test a été refusée)

$ az group delete -n rg-test-region --yes --no-wait
```

Le groupe de test est vide. Sa suppression ne concerne donc aucune ressource payante.

### Restrictions constatées

- **Région** : 5 régions autorisées par la règle « Allowed resource deployment regions ». France Central est refusée (`RequestDisallowedByAzure`).
- **Denmark East** : autorisée, mais Azure Container Apps n'y est pas disponible.
- **Germany West Central**, proposée plus haut, est **refusée** sur cet abonnement.

---

## Décision finale

| Région | Abonnement de secours (Nicolas) | Abonnement du projet (Mathis) |
|---|---|---|
| `italynorth` | ✔ | ✔ |
| `spaincentral` | ✔ | ✔ |
| `belgiumcentral` | ✔ | ✔ |
| `germanywestcentral` | ✔ | ✘ |
| `norwayeast` | ✘ | ✔ |

- **Abonnement utilisé pour le déploiement :** celui de Mathis. Celui de Nicolas reste en secours.
- **Région retenue : `italynorth`** (Milan).
  - Elle est autorisée **sur les deux abonnements**, avec Container Apps, ACR et Log Analytics disponibles. En cas de bascule sur l'abonnement de secours, `deploy.sh` fonctionne sans changer `LOCATION`.
  - C'est une région en service depuis 2023, plus éprouvée que Belgium Central, ouverte plus récemment.
  - Elle est proche de la région Neon Frankfurt (J5), ce qui limite la latence entre le backend et la base.
- **Restrictions à signaler au formateur :** liste de régions imposée et différente selon le compte étudiant, et France Central refusée.
