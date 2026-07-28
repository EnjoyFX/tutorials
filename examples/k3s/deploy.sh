#!/bin/sh
set -eu

CDPATH=
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-myapp}"
IMAGE_TAG="${IMAGE_TAG:-local}"
IMAGE="${IMAGE_REPOSITORY}:${IMAGE_TAG}"
RELEASE="${RELEASE:-myapp}"
NAMESPACE="${NAMESPACE:-demo}"
TIMEOUT="${TIMEOUT:-2m}"
CHART="${CHART:-$SCRIPT_DIR/../helm/myapp}"

for cmd in docker kubectl helm sudo; do
  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

# 1. Build
echo "==> Building image..."
docker build -t "$IMAGE" "$SCRIPT_DIR/../docker"

# 2. Import into k3s (bypasses registry)
echo "==> Importing image into k3s..."
docker save "$IMAGE" | sudo k3s ctr images import -

# 3. Namespace
echo "==> Ensuring namespace '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 4. Deploy
echo "==> Deploying '$RELEASE' via Helm..."
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --set image.repository="$IMAGE_REPOSITORY" \
  --set image.tag="$IMAGE_TAG" \
  --set image.pullPolicy=Never \
  --atomic \
  --timeout "$TIMEOUT" \
  --wait

echo ""
echo "==> Done. To access the app:"
echo "    kubectl port-forward service/${RELEASE}-myapp 8080:8080 -n $NAMESPACE"
echo "    curl http://localhost:8080/"
echo "    curl http://localhost:8080/health"
