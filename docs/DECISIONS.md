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
