# RAG ONE ID — Infra Kubernetes (PROD)

Dépôt local (pas de remote) contenant les manifests Kubernetes de
production pour le projet RAG ONE ID, sur le modèle du dépôt
`appel-offre-k8s` (AO-ID).

**Cluster cible** : le même que AO-ID (cluster ONE ID), namespace `numa`.
Gateway `gw01` (Envoy Gateway), IP `10.13.1.104`. Registre d'images
`apicall.one-id.fr/numa/...`. StorageClass `ceph-rbd`.

## Composants déployés

| Fichier | Rôle |
|---|---|
| `01-secrets.yaml` | Secret `rag-id-secrets` (référence, valeurs vides — à créer en CLI) |
| `02-pvc.yaml` | PVC `rag-id-data` (SQLite historique, ceph-rbd, RWO, 2Gi) |
| `03-qdrant.yaml` | StatefulSet + Service `qdrant` (base vectorielle intra-cluster, v1.12.4) |
| `04-deployment-rag-id.yaml` | Deployment + Service `rag-id` (API RAG, port 8080 → Service 80) |
| `05-httproute.yaml` | HTTPRoute `ragid.one-id.fr` via gw01 (https + http) |
| `06-netpol-rag-id.yaml` | NetworkPolicy ingress 8080 sur le pod rag-id |
| `07-netpol-qdrant.yaml` | NetworkPolicy ingress 6333/6334 sur qdrant depuis rag-id |
| `08-netpol-egress-rag-id.yaml` | NetworkPolicy egress rag-id (DNS + 443 + Qdrant) |
| `09-backendtrafficpolicy-rag-id.yaml` | BackendTrafficPolicy Envoy (timeout 240s) |

## Ordre d'application

Le namespace `numa` existe déjà (créé par AO-ID) — **ne pas le recréer**.

```
kubectl -n numa create secret generic rag-id-secrets ...   # voir docs/EXPLOITATION.md
kubectl apply -f 02-pvc.yaml
kubectl apply -f 03-qdrant.yaml
kubectl apply -f 04-deployment-rag-id.yaml
kubectl apply -f 05-httproute.yaml
kubectl apply -f 06-netpol-rag-id.yaml
kubectl apply -f 07-netpol-qdrant.yaml
kubectl apply -f 08-netpol-egress-rag-id.yaml
kubectl apply -f 09-backendtrafficpolicy-rag-id.yaml
```

## Étapes post-déploiement (OBLIGATOIRES)

1. **DNS** : créer `ragid.one-id.fr` → `10.13.1.104` côté infra.
2. **Azure AD** : enregistrer l'URI de redirection
   `https://ragid.one-id.fr/auth/callback` sur l'app registration.
3. **Réimport des vecteurs Qdrant** : le Qdrant du cluster démarre **vide**.
   La base vectorielle (~110 Mo, collection `onenote_kbid`) doit être
   réimportée après le premier déploiement. Voir `docs/EXPLOITATION.md`
   (étape non couverte par ces manifests).

## Procédure de bascule

Voir le skill `prod_k8s` (rédigé pour AO-ID — à adapter pour RAG).

**Important** : ces manifests ne sont PAS déployés. Un humain valide et
applique. Aucun `kubectl apply` n'a été exécuté depuis ce dépôt.
