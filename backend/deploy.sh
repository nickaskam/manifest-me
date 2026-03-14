#!/bin/bash
# ManifestMe Cloud Run deploy script
# Usage: ./deploy.sh [api|worker|all]
set -e

PROJECT="manifest-me-app"
REGION="us-central1"
REPO="us-central1-docker.pkg.dev/${PROJECT}/manifest-me"
TARGET="${1:-all}"

# ── Logging helpers ────────────────────────────────────────────────────────────
log()  { echo ""; echo "▸ $*"; }
ok()   { echo "  ✅ $*"; }
warn() { echo "  ⚠️  $*"; }
step() { echo "  → $*"; }

# ── Cleanup ────────────────────────────────────────────────────────────────────
cleanup() { rm -f Dockerfile; }
trap cleanup EXIT

# ── Deploy functions ───────────────────────────────────────────────────────────
deploy_api() {
  log "STEP 1/2 — Building API image"
  step "Copying Dockerfile.api → Dockerfile"
  cp Dockerfile.api Dockerfile

  step "Uploading source to Cloud Build (this takes ~30s)..."
  gcloud builds submit --tag "${REPO}/api:latest" . \
    --suppress-logs 2>&1 | grep -E "(Creating|Uploading|BUILD|PUSH|Finished|ERROR|Step)" || true

  ok "Image built and pushed: ${REPO}/api:latest"
  rm Dockerfile

  log "STEP 2/2 — Deploying API to Cloud Run"
  step "Sending to Cloud Run (region: ${REGION})..."
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

  ok "API deployed → https://manifest-me-api-79704250837.us-central1.run.app"
}

deploy_worker() {
  log "STEP 1/2 — Building Worker image"
  step "Copying Dockerfile.worker → Dockerfile"
  cp Dockerfile.worker Dockerfile

  step "Uploading source to Cloud Build (this takes ~30s)..."
  gcloud builds submit --tag "${REPO}/worker:latest" . \
    --suppress-logs 2>&1 | grep -E "(Creating|Uploading|BUILD|PUSH|Finished|ERROR|Step)" || true

  ok "Image built and pushed: ${REPO}/worker:latest"
  rm Dockerfile

  log "STEP 2/2 — Deploying Worker to Cloud Run"
  step "Sending to Cloud Run (4GB RAM, 2 CPUs, 1hr timeout)..."
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

  ok "Worker deployed."
}

# ── Main ───────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════╗"
echo "║     ManifestMe — Cloud Run Deploy    ║"
echo "╚══════════════════════════════════════╝"
echo "  Project : ${PROJECT}"
echo "  Region  : ${REGION}"
echo "  Target  : ${TARGET}"

if [ "$TARGET" = "api" ]; then
  deploy_api
elif [ "$TARGET" = "worker" ]; then
  deploy_worker
else
  deploy_api
  deploy_worker
fi

echo ""
echo "🎉 Deploy complete."
