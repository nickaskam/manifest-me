#!/bin/bash
# ManifestMe Cloud Run deploy script
# Usage: ./deploy.sh [api|worker|all]
set -e

PROJECT="manifest-me-app"
REGION="us-central1"
REPO="us-central1-docker.pkg.dev/${PROJECT}/manifest-me"

TARGET="${1:-all}"

deploy_api() {
  echo "🔨 Building API image..."
  gcloud builds submit \
    --tag "${REPO}/api:latest" \
    --file Dockerfile.api \
    .

  echo "🚀 Deploying API to Cloud Run..."
  gcloud run deploy manifest-me-api \
    --image "${REPO}/api:latest" \
    --region "${REGION}" \
    --platform managed \
    --allow-unauthenticated \
    --min-instances 1 \
    --max-instances 10 \
    --memory 512Mi \
    --cpu 1 \
    --timeout 60 \
    --set-env-vars "GOOGLE_CLOUD_PROJECT=${PROJECT}"
}

deploy_worker() {
  echo "🔨 Building Worker image..."
  gcloud builds submit \
    --tag "${REPO}/worker:latest" \
    --file Dockerfile.worker \
    .

  echo "🚀 Deploying Worker to Cloud Run..."
  gcloud run deploy manifest-me-worker \
    --image "${REPO}/worker:latest" \
    --region "${REGION}" \
    --platform managed \
    --no-allow-unauthenticated \
    --min-instances 0 \
    --max-instances 5 \
    --memory 4Gi \
    --cpu 2 \
    --cpu-boost \
    --timeout 3600 \
    --set-env-vars "GOOGLE_CLOUD_PROJECT=${PROJECT}"
}

if [ "$TARGET" = "api" ]; then
  deploy_api
elif [ "$TARGET" = "worker" ]; then
  deploy_worker
else
  deploy_api
  deploy_worker
fi

echo "✅ Deploy complete."
