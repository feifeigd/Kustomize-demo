#!/usr/bin/env bash
set -euo pipefail

MANIFEST_URL="${MANIFEST_URL:-https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml}"
AUTO_YES="${AUTO_YES:-false}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl was not found in PATH" >&2
  exit 1
fi

context="$(kubectl config current-context)"

echo "Current kubectl context: ${context}"
echo "Flannel manifest: ${MANIFEST_URL}"

if [[ "${AUTO_YES}" != "true" ]]; then
  read -r -p "Install flannel into this cluster? Type 'yes' to continue: " answer
  if [[ "${answer}" != "yes" ]]; then
    echo "Canceled."
    exit 0
  fi
fi

echo "Applying flannel manifest..."
kubectl apply -f "${MANIFEST_URL}"

echo "Waiting for flannel daemonset to become available..."
kubectl rollout status daemonset/kube-flannel-ds \
  -n kube-flannel \
  --timeout=180s

echo
echo "Flannel installed. Useful checks:"
echo "  kubectl get pods -n kube-flannel -o wide"
echo "  kubectl get nodes -o wide"
echo "  kubectl get pods -n demo-dev"

