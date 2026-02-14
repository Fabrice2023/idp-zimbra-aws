# 🚀 Guide de Démarrage Rapide - IDP Zimbra

Guide pour démarrer avec l'IDP Zimbra en 30 minutes.

## Prérequis Rapide
```bash
# Vérifier que tout est installé
docker --version
kind version
kubectl version --client
helm version
```

## Installation en 5 Étapes

### 1. LocalStack (2 min)
```bash
docker run -d --name localstack -p 4566:4566 \
  -e PERSISTENCE=1 -e SERVICES=s3,ec2,rds,iam,vpc \
  -v ~/localstack-data:/var/lib/localstack \
  localstack/localstack
```

### 2. Cluster Kind (1 min)
```bash
kind create cluster --name idp
```

### 3. Crossplane (3 min)
```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system --create-namespace \
  --version 1.17.1 --wait
```

### 4. Providers (10-15 min avec VPN)
```bash
# Activer WARP si MTN
warp-cli connect

# Installer providers
cd ~/Documents/idp-zimbra-aws
kubectl apply -f crossplane/providers/
kubectl get providers -w  # Attendre HEALTHY=True
```

### 5. Configuration (5 min)
```bash
# Secrets
kubectl create secret generic aws-creds -n crossplane-system \
  --from-literal=creds='[default]
aws_access_key_id = test
aws_secret_access_key = test'

# ProviderConfig + RBAC + CRD
kubectl apply -f platform/crossplane/provider-config.yaml
kubectl apply -f platform/rbac/

# XRD + Composition
kubectl apply -f crossplane/xrds/xzimbra.yaml
kubectl apply -f crossplane/compositions/zimbra-platform.yaml
```

## Premier Déploiement
```bash
# Créer un claim
cat <<YAML | kubectl apply -f -
apiVersion: idp.example.com/v1alpha1
kind: Zimbra
metadata:
  name: test-zimbra
spec:
  environment: dev
  region: us-east-1
  storageSizeGB: 50
  instanceType: t3.medium
YAML

# Surveiller
kubectl get zimbra,bucket,vpc -w
```

## Vérification
```bash
# Tout doit être SYNCED=True READY=True
kubectl get bucket
kubectl get vpc,subnet,internetgateway

# Dans LocalStack
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
aws --endpoint-url=http://localhost:4566 s3 ls
aws --endpoint-url=http://localhost:4566 ec2 describe-vpcs
```

## Troubleshooting Express

**Providers pas HEALTHY ?**
```bash
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3
# Si "forbidden" → kubectl apply -f platform/rbac/
```

**Ressources pas SYNCED ?**
```bash
kubectl describe bucket <name>
# Voir l'erreur dans Events
```

**LocalStack pas accessible ?**
```bash
docker ps | grep localstack
docker logs localstack
```

---

**Temps total** : ~30 minutes  
**Résultat** : Infrastructure S3 + VPC fonctionnelle automatiquement créée via un simple fichier YAML !
