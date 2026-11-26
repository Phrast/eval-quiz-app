# J4 — Diagnostic : de quoi le backend a-t-il besoin pour démarrer ?

**Date :** 26/11/2026
**Image testée :** `acrquizmb2611.azurecr.io/quiz-backend:832fb4c` (image v2 déployée sur Azure), lancée en local, **sans aucune base de données**.

**Hypothèse :** le backend ne dépend pas de PostgreSQL pour démarrer (`pg.Pool` ne se connecte qu'à la première requête), mais il dépend de la clé Resend (`new Resend(process.env.RESEND_API_KEY)` au chargement de `server.js`).

## Test 1 : `RESEND_API_KEY` vide

```console
$ docker run --rm -e RESEND_API_KEY= acrquizmb2611.azurecr.io/quiz-backend:832fb4c
file:///app/node_modules/resend/dist/index.mjs:312
        throw new Error(
              ^
Error: Missing API key. Pass it to the constructor `new Resend("re_123")`
    at new Resend (file:///app/node_modules/resend/dist/index.mjs:312:15)
    at file:///app/server.js:55:16
    [...]
Node.js v22.23.5
code retour = 1
```

Le processus **s'arrête immédiatement** (code 1), à la ligne 55 de `server.js`. Sur Azure, la révision redémarrerait en boucle.

## Test 2 : `RESEND_API_KEY` factice, aucune base

```console
$ docker run --rm -d --name t-j4 -e RESEND_API_KEY=re_factice -p 13007:3007 acrquizmb2611.azurecr.io/quiz-backend:832fb4c
$ curl -i localhost:13007/health
HTTP/1.1 200 OK
{"status":"ok"}

$ curl -sS -o /dev/null -w "HTTP %{http_code}\n" -X POST -H 'Content-Type: application/json' \
    -d '{"firstname":"t","email":"t@example.com","subject":"docker"}' localhost:13007/api/users
HTTP 500

$ docker logs t-j4 | tail -5
      address: '127.0.0.1',
      port: 5432
    }
  ]
}
$ docker rm -f t-j4
```

- Le backend **démarre** et `/health` répond **200** sans aucune base : cette route ne touche pas PostgreSQL.
- Une route qui utilise la base répond **500**. Le log montre la tentative de connexion vers `127.0.0.1:5432` (refusée) : la connexion n'est tentée qu'à ce moment-là.

## Conclusion

| Dépendance | Nécessaire au démarrage ? | Effet si absente |
|---|---|---|
| `RESEND_API_KEY` (non vide) | **oui** | crash immédiat `Missing API key` |
| PostgreSQL (`DATABASE_URL` joignable) | non | le serveur démarre ; seules les routes `/api/*` qui lisent ou écrivent répondent 500 |

**Conséquences pour le déploiement :**
- `RESEND_API_KEY=re_factice` dans `.env.azure` suffit pour démarrer. L'envoi de l'email échoue alors proprement (try/catch) et le résultat est quand même enregistré.
- En J4, une `DATABASE_URL` factice suffit pour valider le déploiement (`/health` = 200). Les erreurs 500 sur `/api/users` sont attendues jusqu'au branchement de Neon (J5).
