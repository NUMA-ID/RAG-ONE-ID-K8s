# Image de production pour Kubernetes (cluster ONE ID, namespace numa)
# API RAG ONE ID — FastAPI + embeddings BAAI/bge-m3 (CPU).
#
# IMPORTANT — le contexte de build est la RACINE du dépôt applicatif PREPROD,
# pas ce dépôt k8s. Les modules RAG (api, auth, generation, retrieval,
# storage, indexer, ...) vivent à la racine de PREPROD et s'importent avec
# /app comme racine du PYTHONPATH (ex: `from auth.office365 import ...`).
# Ce Dockerfile est donc pointé via -f depuis PREPROD.
#
# Commande de build attendue :
#   cd /home/numa/projets/RAG/PREPROD \
#     && docker build -f /home/numa/projets/RAG-k8s/Dockerfile \
#          -t apicall.one-id.fr/numa/rag-id:1.0 .
#
# Le .dockerignore associé (RAG-k8s/.dockerignore) doit être copié à la
# racine de PREPROD au moment du build, OU on se fie au fait que Docker lit
# le .dockerignore situé à la racine du contexte (PREPROD). Voir note plus bas.

FROM python:3.11-slim

# --- Réglages runtime Python ---
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# --- Dépendances système minimales ---
# torch + sentence-transformers roulent en CPU ; pas de toolchain de build
# nécessaire (roues précompilées sur PyPI). On garde l'image slim.
# curl est ajouté pour permettre une healthcheck HTTP côté cluster si besoin.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# --- Dépendances Python (versions épinglées, requirements.txt tel quel) ---
# Copié seul d'abord pour profiter du cache de couche Docker : tant que
# requirements.txt ne change pas, l'install est réutilisée.
COPY requirements.txt .
# torch est installé EN PREMIER depuis l'index PyPI CPU de PyTorch.
# requirements.txt épingle `torch==2.13.0` (sans variante) ; par défaut pip
# tire la roue GPU qui embarque tout le stack CUDA/cuDNN (plusieurs Go inutiles
# ici : bge-m3 tourne en CPU dans le pod). En installant d'abord
# `torch==2.13.0+cpu` (roue CPU, ~200 Mo), la contrainte `torch==2.13.0` du
# requirements est déjà satisfaite : pip ne réinstalle pas la variante GPU.
# Résultat : image nettement plus légère et build qui tient dans l'espace disque.
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch==2.13.0 \
    && pip install --no-cache-dir -r requirements.txt

# --- Utilisateur non-root créé TÔT (avant le download du modèle et les COPY) ---
# Créé AVANT le pré-téléchargement bge-m3 et les COPY pour que ces gros fichiers
# soient écrits directement avec le bon propriétaire. Cela évite un `chown -R`
# récursif final qui, en dupliquant le cache HF (~2,3 Go) dans un layer
# supplémentaire, gonflait l'image de ~4,5 Go inutiles.
RUN useradd --create-home --uid 10001 appuser

# --- Modèle d'embedding BAAI/bge-m3 : voir les deux options (A/B) ci-dessous ---
#
# HF_HOME est fixé dans le home de appuser : le cache appartient à l'utilisateur
# non-root sans chown, et sert de base à un éventuel PVC monté (persistance du
# modèle entre redémarrages du pod).
ENV HF_HOME=/home/appuser/.cache/huggingface \
    HF_HUB_DISABLE_TELEMETRY=1
#
# OPTION (A) — ACTIVE : pré-télécharger le modèle DANS l'image au build, EN TANT
# QU'appuser (donc pas de chown ensuite). Rend le pod autonome au démarrage :
# aucun egress HuggingFace requis au boot, ce qui colle à la NetworkPolicy
# restrictive du template "Secure Isolated". PRÉREQUIS de build : l'hôte doit
# disposer d'espace suffisant pour torch+deps ET les ~2,3 Go de bge-m3.
# NB : sur djinn-bot le containerd image store (/var/lib/containerd, partition
# /var ~5,9 Go) est trop petit -> builder sur un hôte au stockage plus grand
# (fait : poste Windows / Docker Desktop, 136 Go libres).
USER appuser
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('BAAI/bge-m3', device='cpu')"
#
# OPTION (B) — REPLI (inactif) : le modèle se télécharge au PREMIER usage.
# Nécessiterait un egress HTTPS vers huggingface.co au runtime, ou un PVC
# pré-rempli monté sur HF_HOME. Pour l'activer : retirer le RUN ci-dessus.
USER root

# --- Code applicatif ---
# Les modules RAG sont à la racine de PREPROD -> copiés à la racine de /app.
# Le frontend statique web/ DOIT être présent (api/main.py sert WEB_DIR).
# COPY --chown écrit directement avec le bon propriétaire (pas de chown -R final).
COPY --chown=appuser:appuser api/        /app/api/
COPY --chown=appuser:appuser auth/       /app/auth/
COPY --chown=appuser:appuser generation/ /app/generation/
COPY --chown=appuser:appuser retrieval/  /app/retrieval/
COPY --chown=appuser:appuser storage/    /app/storage/
COPY --chown=appuser:appuser indexer/    /app/indexer/
COPY --chown=appuser:appuser ingestion/  /app/ingestion/
COPY --chown=appuser:appuser parsing/    /app/parsing/
COPY --chown=appuser:appuser scripts/    /app/scripts/
COPY --chown=appuser:appuser web/        /app/web/

USER appuser

# Port 8080 : imposé par la NetworkPolicy du template "Secure Isolated"
# (ingress autorisé uniquement sur certains ports ; le jumeau AO-ID utilise
# 8080). NE PAS utiliser 8082 (port de dev local sur djinn-bot uniquement).
EXPOSE 8080

CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8080"]
