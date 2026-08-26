# Journal des blocages — RAG-k8s

## 2026-08-26 — Aucun manifest écrit, cluster cible non confirmé

**Description** : ce dépôt a été créé par cohérence avec le schéma
AO-ID (`appel-offre-k8s`) mais aucun manifest K8s n'existe encore.
**Cause** : le cluster/namespace cible pour la PROD de RAG ONE ID n'a
pas été explicitement confirmé par l'utilisateur.
**Impact** : bloquant pour toute phase PACK (Dockerfile + manifests).
**État** : ouvert.
**Contournement** : aucun — à lever avant d'écrire le moindre
manifest.
