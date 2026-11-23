# Décisions — RAG ONE ID Infra K8s

## 2026-09-10 — Cluster cible confirmé

Le cluster de production de RAG ONE ID est le **même que AO-ID** (cluster
ONE ID), namespace `numa`. Décidé ce jour. Conventions réutilisées telles
quelles : Gateway `gw01` (Envoy, IP `10.13.1.104`), registre
`apicall.one-id.fr/numa/...`, storageClass `ceph-rbd`, NetworkPolicies
additives, HTTPRoute Gateway API v1 dans le ns applicatif.

## 2026-09-10 — Qdrant dans le cluster (StatefulSet + PVC)

**Choix** : déployer un Qdrant dédié DANS le cluster (StatefulSet 1 replica,
volumeClaimTemplate ceph-rbd 2Gi, image `qdrant/qdrant:v1.12.4`).
**Raison** : isolation de la base vectorielle RAG, identité réseau stable
(`http://qdrant:6333`), stockage persistant propre au projet. Version v1.12.4
imposée par la compat testée avec `qdrant-client==1.12.2` côté appli.
**Écarté** : exposer/réutiliser le Qdrant de djinn-bot (couplage, pas de
contrôle sur sa version ni son cycle de vie).

## 2026-09-10 — 1 replica imposé (SQLite / PVC RWO)

**Choix** : `replicas: 1` pour le Deployment `rag-id`.
**Raison** : l'historique des conversations est un fichier SQLite sur un PVC
`ReadWriteOnce` (un seul pod monteur possible). Scaler horizontalement
corromprait/verrouillerait la base.
**Écarté** : plusieurs replicas (nécessiterait une base partagée type
Postgres et un stockage RWX — hors périmètre actuel).

## 2026-09-10 — Port conteneur 8080 (aligné AO-ID)

**Choix** : port conteneur 8080, Service `rag-id` port 80 → targetPort 8080.
**Raison** : cohérence avec AO-ID et le pattern gw01 (Envoy parle au pod en
HTTP sur 8080 après terminaison TLS). Le Dockerfile RAG (RAG-002) expose 8080.

## 2026-09-10 — Resources 2–4Gi pour bge-m3

**Choix** : requests `memory 2Gi / cpu 500m`, limits `memory 4Gi / cpu 2`.
**Raison** : bge-m3 (embeddings CPU) + torch sont chargés en RAM au démarrage.
Sous 2Gi de requests, risque d'OOM au chargement du modèle. Estimation à
ajuster après observation réelle de la consommation en prod.

## 2026-09-10 — Timeout Envoy 240s (BackendTrafficPolicy)

**Choix** : `requestTimeout: 240s` sur la route rag-id.
**Raison** : les requêtes RAG (retrieval + génération LLM) durent 10–40s+ ;
le client HTTP côté code a un timeout de 240s. On aligne large côté Envoy
(défaut 15s insuffisant, même piège que documenté pour AO-ID).

## 2026-09-11 — Bascule v1.0 → v1.1 (rendu Markdown + suivi conversationnel)

Nouveau tag d'image `apicall.one-id.fr/numa/rag-id:1.1` correspondant au
commit `1172bc9` du dépôt PREPROD (`main`) : rendu Markdown des réponses
assistant (marked+DOMPurify servis localement, aucun CDN runtime, XSS
neutralisé) et suivi conversationnel (`RAGPipeline.ask()` transmet
l'historique borné aux 6 derniers messages via `/api/query`).

Bascule effectuée le 11/09/2026, ~11h05 :
- Build sur poste Windows relais (djinn-bot `/var` insuffisant, ~5,2 Go).
- `DOCKER_BUILDKIT=0` + `--config` sans credsStore (contournement wincred).
- `kubectl set image deploy/rag-id rag-id=…:1.1` → rollout OK.
- Vérifs : `https://ragid.one-id.fr/` → HTTP 200 ; `/api/health` → ok ;
  4 assets Markdown (`static/md-render.{js,css}`, `static/vendor/*`) → 200 ;
  digest pod = digest poussé (`sha256:e68ab4bae90a…`) ;
  `md-render.js` prod = local (7735 o) ;
  aucun secret ni manifest modifié (seul le tag d'image bouge).

Rollback : `kubectl set image deploy/rag-id rag-id=…:1.0` (image 1.0
toujours présente sur le nœud, imagePullPolicy IfNotPresent).

## 01/10/2026 — Bascule PROD v1.3.0

Image `apicall.one-id.fr/numa/rag-id:1.3.0` (digest
`sha256:b7c766a5938b41571a2eb129b9d991c512981892ee182d623d0a29bde774cc82`),
commit PREPROD `b1806e4`. Déroulé : build Windows 25/09 (vérifié :
prompt Lyra présent dans `generation/fiche_technique.py`,
`SCOPES=["Notes.Read.All","Sites.Read.All"]`, vendor assets) ; push
25/09 ; rollout interrompu le soir même (pas de route réseau domicile →
cluster, cf BLOCAGES #9) ; rollout terminé le 01/10.

Contenu livré : prompt Lyra pour la génération de fiches techniques
(RAG-001), URLs OneNote cliquables dans les sources des fiches
(RAG-002/003, backfill Qdrant fait), fix scopes auth synchro OneNote
(403 SharePoint résolu), bump 1.3.0.

Vérifications 01/10 : rollout OK ; pod imageID = digest poussé ; `/` →
200 ; `/api/health` → ok ; `/api/version` → 1.3.0-beta ; 4 assets
Markdown → 200 ; clé LLM présente en DB PVC (llm_settings non vide,
model gptoss20b) ; test bout en bout `POST /api/query` authentifié via
cookie fabriqué → HTTP 200, réponse + 5 sources citées (le fond "info
non trouvée pour 60F" est une réponse RAG correcte, pas une erreur).

Manifest 04 relevé de 1.1 → 1.3.0 dans le même commit (l'écart
manifest/cluster documenté dans la bascule v1.2.1 est résorbé).

Point sans impact relevé : `/api/version` affiche nb_pages=0 car
`data/onenote_registry.json` n'existe pas sur le PVC prod (le registre
vit sur djinn-bot) — badge informatif seulement.

Rollback : `kubectl -n numa set image deploy/rag-id
rag-id=apicall.one-id.fr/numa/rag-id:1.2.2` (présent sur le nœud).

## 2026-11-23 — Bascule 1.4.8 : historique support CRM 5 ans en PROD

**Décidé** : déployer l'image `1.4.8` (commit applicatif `cb086d3`, mergé sur
`main` et poussé sur GitLab **et** GitHub) et transférer la collection CRM par
snapshot plutôt que par réindexation.

- Image : `apicall.one-id.fr/numa/rag-id:1.4.8`, digest
  `sha256:c2e94505aa194d9909216cfdd9fdc2bd50dd4578fbe8f741754c39f9d0a3ce63`
  — digest du pod vérifié identique à celui du push.
- Données : snapshot de `crm_support_full` (220 Mo, 29 929 points, 25 574
  documents : 21 972 tickets, 2 852 clients, 755 contrats), restauré dans le
  Qdrant du cluster via `POST /collections/crm_support_full/snapshots/upload`.
  Aucune réindexation en PROD : les vecteurs bge-m3 sont identiques, le coût
  d'un backfill (6 h 55 en PREPROD) est évité.
- Manifest : `04-deployment-rag-id.yaml` porte le tag `1.4.8` **et** la
  variable `CRM_SOLUTIONS_COLLECTION=crm_support_full` — sans elle, l'agent
  interroge `crm_support` (l'échantillon de 300 tickets) qui n'existe pas en
  PROD et répond « aucun ticket ».

**Recette réelle dans le pod** (cookie de session signé, pas de login O365) :
21 972 tickets / 52 537 interventions ; « problèmes VINOLEM » → 8 tickets,
125 tickets au compteur, 4 sources citées ; « TT032950 » → référence exacte,
client LES SENIORIALES, interventions datées.

**Défaut connu, non bloquant** : sur une question qui ne nomme aucun client
mais contient un nom de produit (« erreur de sauvegarde VEEAM »), le modèle
ajoute de lui-même un filtre `client` inventé et le compteur tombe à zéro.
Le tool est correct (vérifié : 3 résultats sans filtre) ; c'est la sélection
d'outil/paramètre qui doit être corrigée (règle de prompt + repli du tool
« aucun ticket pour ce client, réessayez sans filtre »).

Rollback : `kubectl -n numa set image deploy/rag-id
rag-id=apicall.one-id.fr/numa/rag-id:1.4.7` (image du nœud) puis
`kubectl apply` du manifest précédent pour retirer la variable.
