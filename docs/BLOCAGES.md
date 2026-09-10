# Journal des blocages — RAG-k8s

## 2026-08-26 — Aucun manifest écrit, cluster cible non confirmé — RÉSOLU

**Description** : ce dépôt a été créé par cohérence avec le schéma
AO-ID (`appel-offre-k8s`) mais aucun manifest K8s n'existait encore.
**Cause** : le cluster/namespace cible pour la PROD de RAG ONE ID n'avait
pas été explicitement confirmé.
**État** : **RÉSOLU le 2026-09-10**. Cluster cible confirmé = **le même
que AO-ID** (cluster ONE ID), namespace `numa` (cf `docs/DECISIONS.md`).
Le jeu complet de manifests a été écrit (voir `README.md`).

## 2026-09-10 — Réimport des vecteurs Qdrant après premier déploiement — OUVERT

**Description** : le Qdrant déployé dans le cluster (StatefulSet, PVC ceph-rbd
vierge) démarre **vide**. La collection vectorielle `onenote_kbid` (~110 Mo)
doit être réimportée après le premier déploiement.
**Impact** : tant que le réimport n'est pas fait, les requêtes RAG ne
retournent aucune source pertinente (`/api/health` peut pourtant répondre 200).
**État** : ouvert — étape opérationnelle post-déploiement, NON couverte par
les manifests. Procédure décrite dans `docs/EXPLOITATION.md` §5 (script
d'indexation contre `http://qdrant:6333`, ou snapshot/restore Qdrant).

## 2026-09-10 — DNS ragid.one-id.fr à créer côté infra — OUVERT

**Description** : l'exposition HTTPS suppose un enregistrement DNS
`ragid.one-id.fr` → `10.13.1.104` (IP du Gateway gw01).
**Impact** : sans cet enregistrement, l'URL publique n'est pas résoluble
(le TLS wildcard `*.one-id.fr` couvre déjà le certificat).
**État** : ouvert — à créer par l'équipe infra. Documenté dans `README.md`
et `docs/EXPLOITATION.md` §4. À enregistrer aussi côté Azure AD :
`https://ragid.one-id.fr/auth/callback`.
