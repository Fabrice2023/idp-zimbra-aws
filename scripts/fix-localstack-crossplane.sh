#!/usr/bin/env bash
# Script de correction : Crossplane + LocalStack (secret aws-creds, ProviderConfig default, endpoint 172.17.0.1:4566)
# Usage : depuis la racine du projet, ./scripts/fix-localstack-crossplane.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Suppression de l'ancien secret aws-localstack-creds (si présent)..."
kubectl delete secret aws-localstack-creds -n crossplane-system --ignore-not-found=true

echo "==> Application du secret aws-creds et du ProviderConfig default..."
kubectl apply -f "$REPO_ROOT/platform/crossplane/aws-secrets.yaml"
kubectl apply -f "$REPO_ROOT/platform/crossplane/provider-config.yaml"

echo "==> Redémarrage du provider AWS (S3) pour prise en compte des nouveaux credentials..."
# Provider Upbound AWS : déploiement souvent nommé provider-aws-* ou upbound-provider-family-aws-*
DEPLOY=$(kubectl get deployments -n crossplane-system -o name 2>/dev/null | grep -E 'provider.*aws|aws.*provider' | head -1)
if [[ -n "$DEPLOY" ]]; then
  kubectl rollout restart -n crossplane-system "$DEPLOY"
  kubectl rollout status -n crossplane-system "$DEPLOY" --timeout=120s
  echo "    Redémarrage terminé : $DEPLOY"
else
  echo "    Aucun déploiement provider AWS trouvé. Redémarrage manuel possible avec :"
  echo "    kubectl rollout restart deployment -n crossplane-system -l pkg.crossplane.io/provider=<nom-du-provider-aws>"
  echo "    ou : kubectl delete pods -n crossplane-system -l pkg.crossplane.io/provider=<nom-du-provider-aws>"
fi

echo "==> Vérification du bucket zimbra-backup-storage (kubectl get bucket)..."
kubectl get bucket zimbra-backup-storage 2>/dev/null || true

echo "==> Fin. Si le bucket reste SYNCED: False, vérifier : kubectl describe bucket zimbra-backup-storage"
