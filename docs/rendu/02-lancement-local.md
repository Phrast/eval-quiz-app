# Lancement local

## Prérequis

Docker et Docker Compose (Docker Desktop).

## Lancer

```bash
cp .env.example .env          # puis remplacer les mots de passe et JWT_SECRET
docker compose up -d --build
docker compose ps             # 3 services "Up", dont db et backend "healthy"
```

`RESEND_API_KEY` ne doit pas être vide. Sans clé Resend, gardez une valeur factice : l'envoi d'email échoue, mais le reste fonctionne.

## Accès

| Page | URL |
|---|---|
| Quiz | http://localhost:8087 |
| Administration | http://localhost:8087/gestion-quiz (identifiants `ADMIN_USERNAME` / `ADMIN_PASSWORD` du `.env`) |
| Santé du backend | http://localhost:8087/health |

## Arrêter et réinitialiser

| Commande | Effet |
|---|---|
| `docker compose down` | supprime les conteneurs et les réseaux, **garde les données** |
| `docker compose down -v` | supprime aussi le volume : **toutes les données sont perdues**, et `init.sql` est rejoué au démarrage suivant |
| `docker compose logs -f backend` | suit les logs du backend |
