# J2 — Sécurité des images (Trivy)

**Date :** 26/11/2026 · **Outil :** Trivy 0.76.2 (`ghcr.io/aquasecurity/trivy`, épinglé par digest)

## Résultat avant / après

| Image | Version | Image de base | Taille | CRITICAL | HIGH | MEDIUM | LOW |
|---|---|---|---|---|---|---|---|
| backend | v1 | `node:22` (Debian 12) | 1,66 Go | 20 | 480 | 1408 | 1563 |
| backend | v2 | `node:22.23.5-alpine3.24` | 273 Mo | **0** | **0** | 2 | 0 |
| frontend | v1 | `nginx:1.30` (Debian 13) | 240 Mo | 1 | 72 | 131 | 178 |
| frontend | v2 | `nginx:1.30.8-alpine3.24` | 103 Mo | **0** | **0** | 0 | 0 |

Analyse des Dockerfiles (`trivy config`) :
- **v1** : 2 alertes sur chaque Dockerfile, `DS-0002` (HIGH, pas de `USER`, donc exécution en root) et `DS-0026` (LOW, pas de `HEALTHCHECK`) ;
- **v2** : aucune alerte.

Rapports complets : `avant-*.txt` et `apres-*.txt` (HIGH et CRITICAL), `avant-config.txt` et `apres-config.txt`.

## Problèmes relevés en v1

- **Backend** : presque toutes les failles viennent des paquets Debian de l'image `node:22` complète (outils de compilation, bibliothèques graphiques…), inutiles pour exécuter l'API. Les 10 HIGH « Node.js » viennent du `npm` embarqué dans l'image, pas de l'application.
- **Frontend** : les failles viennent des paquets Debian de l'image `nginx`, dont la CRITICAL `libxml2`, qui n'a pas de correctif.
- **Les deux images** : le processus tourne en root.

## Corrections

| Correction | Effet |
|---|---|
| Images de base Alpine | beaucoup moins de paquets système, donc moins de failles ; images 2 à 6 fois plus petites |
| Build en plusieurs étapes | les outils de build (npm, Vite) ne sont pas dans l'image finale |
| Suppression de npm, yarn et corepack dans le backend | élimine les 10 HIGH « Node.js » : ces outils sont inutiles pour `node server.js` |
| `apk upgrade` | applique les correctifs système publiés après l'image de base |
| nginx officiel **1.30.8** au lieu de `nginx-unprivileged` 1.30.6 | l'image `nginx-unprivileged` avait du retard : sa version de nginx contenait 4 CRITICAL et 2 HIGH, corrigées en 1.30.7 |
| Utilisateur non-root (`node`, `nginx`) | une faille dans l'application ne donne pas les droits root dans le conteneur |
| `tini` comme PID 1 (backend) | les signaux d'arrêt sont transmis à Node : arrêt propre |
| Versions épinglées | builds reproductibles, pas de changement surprise |
| `HEALTHCHECK` dans les deux images | Docker sait si le service répond |

## Vulnérabilités résiduelles

| Paquet (backend) | Sévérité | Pourquoi on l'accepte |
|---|---|---|
| `glob` 10.5.0 (CVE-2026-118773), `minimatch` 9.0.9 (CVE-2026-118764) | MEDIUM | dépendances indirectes de `resend` (`resend` → `@react-email/render` → `pretty` → `js-beautify`), qui servent à générer des emails depuis des composants React. L'application envoie directement du HTML, donc ce code n'est pas utilisé. Le correctif impose une nouvelle version majeure de `resend`, c'est-à-dire une modification du code applicatif, hors périmètre |

## Politique pour la CI

Une vulnérabilité **CRITICAL** fait échouer le contrôle. Vérification sur les images v2 :

```console
$ trivy image --severity CRITICAL --exit-code 1 quiz-backend:v2    → code retour 0
$ trivy image --severity CRITICAL --exit-code 1 quiz-frontend:v2   → code retour 0
```

## Non-régression

Avec les images v2, l'application fonctionne entièrement : santé, quiz, admin, inscription, enregistrement et email. Les conteneurs tournent en `uid=1000(node)` et `uid=101(nginx)`, et les données sont conservées.

## Commandes utilisées

```bash
docker tag quiz-backend:local quiz-backend:v1        # idem pour le frontend ; v2 après reconstruction
trivy image --severity HIGH,CRITICAL -o preuves/J2/avant-backend.txt quiz-backend:v1
trivy config -o preuves/J2/avant-config.txt .
docker compose up -d --build --wait                  # reconstruction avec les Dockerfiles v2
trivy image --severity HIGH,CRITICAL -o preuves/J2/apres-backend.txt quiz-backend:v2
trivy image --severity CRITICAL --exit-code 1 quiz-backend:v2
```
