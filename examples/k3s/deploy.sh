#!/bin/sh
set -e

IMAGE="myapp:latest"
RELEASE="myapp"
NAMESPACE="demo"
CHART="$(dirname "$0")/../helm/myapp"

# 1. Build
echo "==> Building image..."
docker build -t "$IMAGE" "$(dirname "$0")/../docker"

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
  --set image.pullPolicy=Never \
  --wait

echo ""
echo "==> Done. To access the app:"
echo "    kubectl port-forward service/${RELEASE}-myapp 8080:8080 -n $NAMESPACE"
echo "    curl http://localhost:8080/"
echo "    curl http://localhost:8080/health"
