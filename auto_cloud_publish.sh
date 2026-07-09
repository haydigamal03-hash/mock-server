#!/usr/bin/env bash
set -euo pipefail

# auto_cloud_publish.sh
# Usage:
#   chmod +x auto_cloud_publish.sh
#   ./auto_cloud_publish.sh <github-repo-name> <visibility> <ghcr|dockerhub> <docker-username>
#
# Example:
#   ./auto_cloud_publish.sh b2b-web3-rpc-service private ghcr my-gh-username

REPO_NAME="${1:-b2b-web3-rpc-service}"
VISIBILITY="${2:-private}"        # private or public
REGISTRY_CHOICE="${3:-ghcr}"      # ghcr or dockerhub
DOCKER_USER="${4:-}"              # required for dockerhub; for ghcr use your GH username

# Requirements: gh (authenticated), git, kubectl (for kubeconfig), docker (optional)
command -v gh >/dev/null 2>&1 || { echo "gh CLI required and must be authenticated. Aborting."; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git required. Aborting."; exit 1; }

GH_USER="$(gh api user --jq .login)"
echo "GitHub user: $GH_USER"

# 1) Initialize git repo if needed and commit current tree
if [ ! -d .git ]; then
  git init
  git add .
  git commit -m "Initial scaffold"
else
  git add .
  git commit -m "Prepare for cloud publish" || true
fi

# 2) Create GitHub repo (private/public)
if [ "$VISIBILITY" != "private" ] && [ "$VISIBILITY" != "public" ]; then
  echo "Visibility must be 'private' or 'public'."
  exit 1
fi

echo "Creating GitHub repo ${GH_USER}/${REPO_NAME} (${VISIBILITY})..."
gh repo create "${GH_USER}/${REPO_NAME}" --"${VISIBILITY}" --confirm --description "Auto-published by auto_cloud_publish.sh"

git remote add origin "git@github.com:${GH_USER}/${REPO_NAME}.git" 2>/dev/null || git remote set-url origin "git@github.com:${GH_USER}/${REPO_NAME}.git"
git branch -M main
git push -u origin main --force

# 3) Create GitHub Actions workflow for build/push/deploy
mkdir -p .github/workflows
cat > .github/workflows/ci-deploy.yml <<'YML'
name: Build, Push and Deploy

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    env:
      IMAGE_TAG: ${{ github.sha }}
    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v2

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Login to registry
        if: ${{ secrets.REGISTRY == 'ghcr' }}
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: ${{ secrets.GHCR_USERNAME }}
          password: ${{ secrets.GHCR_TOKEN }}

      - name: Login to DockerHub
        if: ${{ secrets.REGISTRY == 'dockerhub' }}
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build and push backend image
        run: |
          IMAGE="${{ secrets.REGISTRY_HOST }}/${{ secrets.REGISTRY_USER }}/b2b-web3-backend:${{ env.IMAGE_TAG }}"
          docker build -t "$IMAGE" -f Dockerfile.backend .
          docker push "$IMAGE"
        env:
          DOCKER_BUILDKIT: 1

      - name: Build and push frontend image
        run: |
          IMAGE="${{ secrets.REGISTRY_HOST }}/${{ secrets.REGISTRY_USER }}/b2b-web3-frontend:${{ env.IMAGE_TAG }}"
          docker build -t "$IMAGE" -f frontend-admin/Dockerfile.frontend frontend-admin
          docker push "$IMAGE"
        env:
          DOCKER_BUILDKIT: 1

  deploy:
    needs: build-and-push
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup kubectl
        uses: azure/setup-kubectl@v3
        with:
          version: 'latest'

      - name: Restore kubeconfig
        run: |
          echo "${{ secrets.KUBE_CONFIG_BASE64 }}" | base64 --decode > kubeconfig
          export KUBECONFIG=$PWD/kubeconfig
          kubectl config view
      - name: Apply manifests
        run: |
          export KUBECONFIG=$PWD/kubeconfig
          sed -i "s|__BACKEND_IMAGE__|${{ secrets.REGISTRY_HOST }}/${{ secrets.REGISTRY_USER }}/b2b-web3-backend:${{ github.sha }}|g" deploy/backend-deployment.yaml
          sed -i "s|__FRONTEND_IMAGE__|${{ secrets.REGISTRY_HOST }}/${{ secrets.REGISTRY_USER }}/b2b-web3-frontend:${{ github.sha }}|g" deploy/frontend-deployment.yaml
          kubectl apply -f deploy/postgres-statefulset.yaml
          kubectl apply -f deploy/redis-deployment.yaml
          kubectl apply -f deploy/backend-deployment.yaml
          kubectl apply -f deploy/backend-service.yaml
          kubectl apply -f deploy/frontend-deployment.yaml
          kubectl apply -f deploy/frontend-service.yaml
          kubectl apply -f deploy/ingress.yaml
YML

git add .github/workflows/ci-deploy.yml
git commit -m "Add CI/CD workflow" || true
git push origin main

# 4) Prepare and set GitHub Secrets
echo "Configuring GitHub secrets..."

# Determine registry host and user
if [ "$REGISTRY_CHOICE" = "ghcr" ]; then
  REG_HOST="ghcr.io"
  REG_USER="$GH_USER"
  echo "Using GHCR: $REG_HOST / $REG_USER"
  # Ask for GHCR token (personal access token with packages:write, repo)
  read -s -p "Enter GHCR token (personal access token with packages:write and repo scopes): " GHCR_TOKEN
  echo
  gh secret set REGISTRY --body "ghcr"
  gh secret set REGISTRY_HOST --body "$REG_HOST"
  gh secret set REGISTRY_USER --body "$REG_USER"
  gh secret set GHCR_USERNAME --body "$GH_USER"
  gh secret set GHCR_TOKEN --body "$GHCR_TOKEN"
else
  # dockerhub
  if [ -z "$DOCKER_USER" ]; then
    read -p "Enter DockerHub username: " DOCKER_USER
  fi
  read -s -p "Enter DockerHub token/password: " DOCKERHUB_TOKEN
  echo
  gh secret set REGISTRY --body "dockerhub"
  gh secret set REGISTRY_HOST --body "docker.io"
  gh secret set REGISTRY_USER --body "$DOCKER_USER"
  gh secret set DOCKERHUB_USERNAME --body "$DOCKER_USER"
  gh secret set DOCKERHUB_TOKEN --body "$DOCKERHUB_TOKEN"
fi

# Kubeconfig: read from local kubeconfig or ask user to paste base64
if kubectl config view >/dev/null 2>&1; then
  KCFG_PATH="${KUBECONFIG:-$HOME/.kube/config}"
  echo "Found kubeconfig at $KCFG_PATH"
  KCFG_B64=$(base64 -w0 < "$KCFG_PATH")
  gh secret set KUBE_CONFIG_BASE64 --body "$KCFG_B64"
else
  echo "kubectl not configured locally or kubeconfig not found."
  echo "You can paste base64-encoded kubeconfig now (or press Enter to skip):"
  read -r KCFG_B64_INPUT
  if [ -n "$KCFG_B64_INPUT" ]; then
    gh secret set KUBE_CONFIG_BASE64 --body "$KCFG_B64_INPUT"
  else
    echo "Skipping kubeconfig secret. You will need to set KUBE_CONFIG_BASE64 manually in repo secrets."
  fi
fi

# Optional: set other secrets from .env (safe keys only)
if [ -f .env ]; then
  echo "Setting selected .env values as GitHub secrets (DB credentials)"
  POSTGRES_USER=$(grep -E '^POSTGRES_USER=' .env | cut -d'=' -f2- || echo postgres)
  POSTGRES_PASSWORD=$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d'=' -f2- || echo postgres)
  POSTGRES_DB=$(grep -E '^POSTGRES_DB=' .env | cut -d'=' -f2- || echo b2b_web3)
  gh secret set POSTGRES_USER --body "$POSTGRES_USER"
  gh secret set POSTGRES_PASSWORD --body "$POSTGRES_PASSWORD"
  gh secret set POSTGRES_DB --body "$POSTGRES_DB"
fi

echo "All secrets configured (or skipped where not provided)."

# 5) Trigger workflow dispatch to start build & deploy
echo "Triggering workflow dispatch..."
gh workflow run ci-deploy.yml -f

echo "Done. Check Actions tab in the repository: https://github.com/${GH_USER}/${REPO_NAME}/actions"
