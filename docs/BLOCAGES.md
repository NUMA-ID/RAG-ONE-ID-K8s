---
projet: RAG ONE ID
type: blocages
maj: 2026-09-10
---

# Blocages et Points à Résoudre — RAG ONE ID v1.0.0

## 1. Qdrant StatefulSet : Permission Denied sur PVC Ceph RBD

**État** : RÉSOLU (10/09, diagnostic infra)

**Cause racine réelle** (le PVC/Ceph RBD n'était PAS en cause, contrairement à
l'hypothèse initiale) : l'image `qdrant/qdrant:v1.12.4` utilise par défaut des
chemins RELATIFS résolus depuis le CWD `/qdrant` :
- `storage_path: ./storage` → `/qdrant/storage` (monté sur le PVC : OK)
- `snapshots_path: ./snapshots` → `/qdrant/snapshots` (couche image, root:root
  755, PAS monté : KO en non-root)

En `runAsNonRoot: true` / `runAsUser: 1000` (requis par la policy PodSecurity
du cluster), Qdrant ne pouvait pas créer `/qdrant/snapshots` → panic immédiat
au démarrage, avant même de toucher au PVC.

**Correctif appliqué** (`03-qdrant.yaml`) :
1. `env: QDRANT__STORAGE__SNAPSHOTS_PATH=/qdrant/storage/snapshots` — force le
   chemin des snapshots vers un sous-dossier du PVC monté (chemin absolu).
2. `securityContext` repassé à la config saine : `runAsNonRoot: true`,
   `runAsUser: 1000`, `fsGroup: 1000` (les contournements `fsGroup: 0` /
   `runAsNonRoot: false` tentés en session précédente sont retirés).
3. `initContainer` rendu **non-destructif** : `mkdir -p` idempotent uniquement,
   suppression des `rm -f`/`rm -rf` qui effaçaient collections + raft_state à
   CHAQUE redémarrage de pod (voir point 7 ci-dessous, anomalie critique
   distincte détectée par l'infra avant mise en prod réelle avec données).

**Vérifié** : `qdrant-0` 1/1 Running stable, HTTP 6333 listening, `rag-id`
redémarré et reconnecté (health check 200 OK).

**Ancien état (archivé, pour référence)** : OUVERT

**Description** :
- Qdrant (UID 1000) ne peut pas créer de répertoires sur la PVC Ceph RBD montée en `/qdrant/storage`
- Erreur : `Permission denied` lors de la création de `/qdrant/storage/snapshots`
- La PVC est montée avec `root:root 755` — l'utilisateur 1000 ne peut y écrire

**Cause probable** :
- Le `fsGroup: 1000` du pod n'est pas appliqué correctement par Ceph RBD
- C'est une limitation connue Kubernetes + Ceph RBD — `fsGroup` ne fonctionne pas sur tous les storageClass

**Qui peut résoudre** : Fabrice ou Jérémy (infra, gestion Ceph RBD)

**Solutions possibles** :
1. Vérifier la config du storageClass Ceph RBD — doit avoir des permissions d'écriture en groupe
2. Pré-créer les répertoires `/qdrant/storage/snapshots` et `/qdrant/storage/collections` avec les bonnes permissions
3. Utiliser un init container dans le StatefulSet pour créer les répertoires en tant qu'utilisateur 1000

**Impact** : Qdrant est DOWN — pas de base vectorielle. L'API RAG fonctionne mais ne retrouve aucun document pertinent.

**Dépendance** : Bloque la démo complète (retrieval + génération). L'API seule (health check, login) fonctionne.

---

## 2. DNS ragid.one-id.fr manquant

**État** : OUVERT

**Description** :
- L'enregistrement DNS `ragid.one-id.fr` → `10.13.1.104` (Gateway gw01) n'existe pas
- HTTPRoute est configurée mais inaccessible publiquement

**Qui peut résoudre** : Infra ONE ID (gestion DNS)

**Impact** : Impossible d'accéder à `https://ragid.one-id.fr` depuis l'extérieur du cluster

---

## 3. Azure AD Redirect URI non enregistrée

**État** : À VÉRIFIER

**Description** :
- La Redirect URI `https://ragid.one-id.fr/auth/callback` doit être enregistrée sur l'app Azure AD « RAG ONE ID - Web Login »
- App ID: `c573121c-c1bc-4855-893c-e4dfc06f51ab`

**Qui peut résoudre** : Admin Azure AD ONE ID ou propriétaire de l'app

**Impact** : Authentification O365 échouera (`AADSTS50011` redirect URI not registered)

---

## 4. Réimport des vecteurs Qdrant

**État** : RÉSOLU (10/09)

**Procédure appliquée** : snapshot/restore Qdrant natif (pas de réingestion
OneNote complète, plus rapide et fiable) :
1. Snapshot créé sur le Qdrant local djinn-bot : `POST /collections/onenote_kbid/snapshots`
   (9972 points, 114 Mo)
2. Snapshot téléchargé puis transféré vers le cluster via relais Windows
   (`scp` + `kubectl cp` dans le pod `qdrant-0`, chemin `/qdrant/storage/snapshots/`)
3. Restauration via `PUT /collections/onenote_kbid/snapshots/recover` avec
   `location: file:///qdrant/storage/snapshots/onenote_kbid.snapshot`
   (exécuté via un script PowerShell avec `kubectl port-forward` temporaire,
   car l'image Qdrant slim n'a ni `curl` ni `wget`)
4. Vérifié : `points_count: 9972`, `status: green` — identique à la source
5. Fichiers temporaires nettoyés (snapshot supprimé du pod et du poste Windows)

**Résultat** : Qdrant cluster a maintenant les mêmes données que djinn-bot.
Le RAG peut retrouver les documents OneNote KBID en production.

---

## 5. Workflow GitHub Actions : Token permissions insuffisantes

**État** : CONTOURNÉ (déploiement manuel pour v1.0.0)

**Description** :
- Le workflow GitHub Actions échoue sur l'accès au dépôt `RAG-ONE-ID-K8s` (privé)
- Token `ghp_w7...` n'a pas les scopes requis ou l'orga NUMA-ID n'accorde pas l'accès

**Contournement actif** :
- Déploiement manuel (SSH + kubectl) depuis djinn-bot / Windows
- Fonctionne mais lourd pour les futures versions

**Solution** :
- Créer un token GitHub avec scope `repo:all` (accès complet aux dépôts privés NUMA-ID)
- Ou rendre le dépôt `RAG-ONE-ID-K8s` public
- Ou configurer OIDC vers GitHub (meilleure pratique, zéro secret)

---

## 6. Permission d'écriture RAG-ID sur PVC

**État** : RÉSOLU (pour v1.0.0)

**Description** :
- Pod RAG-ID (UID 10001) a besoin d'écrire sur `/app/data/rag_oneid.db` (PVC SQLite)
- Initialement échouait avec `sqlite3.OperationalError: unable to open database file`

**Solution appliquée** :
- Ajout de `fsGroup: 10001` dans le securityContext du Deployment
- Le groupe 10001 peut maintenant écrire sur la PVC

**Statut** : ✅ Fonctionnel pour v1.0.0

---

## 7. Qdrant Permission - Contournement testé mais inefficace

**État** : RÉSOLU — voir point 1 pour la cause racine et le correctif final

**Tentative** :
- Job Kubernetes avec busybox pour pré-créer `/qdrant/storage/snapshots` en tant que UID 1000
- Bloqué sur ContainerCreating (NetworkPolicy empêche le pull d'image ?)

**Résultat** : Job supprimé, solution abandonnée (en attente d'une vraie correction infra)

