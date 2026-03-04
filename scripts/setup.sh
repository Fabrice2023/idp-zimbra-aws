#!/bin/bash

set -e  # Arrêter en cas d'erreur

# Mode d'installation : local (Kind + LocalStack) ou aws (Kind + AWS réel)
MODE="${1:-local}"
if [[ "$MODE" != "local" && "$MODE" != "aws" ]]; then
    echo "Usage: $0 [local|aws]"
    exit 1
fi

# Couleurs pour output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction pour afficher les étapes
step() {
    echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

echo "=================================================="
echo "  🚀 IDP Zimbra AWS - Installation Automatisée"
echo "=================================================="
echo ""

# ============================================
# ÉTAPE 1 : Vérification des prérequis
# ============================================
step "[1/10] Vérification des prérequis..."

# Docker
if ! command -v docker &> /dev/null; then
    error "Docker n'est pas installé. Installez Docker : https://docs.docker.com/get-docker/"
fi
success "Docker $(docker --version | awk '{print $3}')"

# Kind
if ! command -v kind &> /dev/null; then
    error "Kind n'est pas installé. Installez Kind : https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
fi
success "Kind $(kind version | awk '{print $2}')"

# kubectl
if ! command -v kubectl &> /dev/null; then
    error "kubectl n'est pas installé. Installez kubectl : https://kubernetes.io/docs/tasks/tools/"
fi
success "kubectl $(kubectl version --client --short 2>/dev/null | awk '{print $3}')"

# Helm
if ! command -v helm &> /dev/null; then
    error "Helm n'est pas installé. Installez Helm : https://helm.sh/docs/intro/install/"
fi
success "Helm $(helm version --short | awk '{print $1}')"

# jq (requis)
if ! command -v jq &> /dev/null; then
    error "jq n'est pas installé. Installez jq (ex: sudo apt-get install -y jq)"
fi
success "jq $(jq --version)"

# AWS CLI (optionnel pour LocalStack)
if ! command -v aws &> /dev/null; then
    warning "AWS CLI non installé (optionnel, utile pour tester LocalStack)"
else
    success "AWS CLI $(aws --version | awk '{print $1}')"
fi

echo ""

# ============================================
# ÉTAPE 2 : Démarrage de LocalStack
# ============================================
step "[2/10] Démarrage de LocalStack..."

# En mode AWS réel, on ne démarre pas LocalStack
if [[ "$MODE" == "aws" ]]; then
    warning "Mode AWS réel : saut du démarrage LocalStack"
    echo ""
else

# Vérifier si LocalStack tourne déjà
if docker ps | grep -q localstack; then
    warning "LocalStack déjà en cours d'exécution"
else
    # Créer le dossier de persistance
    mkdir -p ~/localstack-data
    
    # Démarrer LocalStack
    docker run -d \
        --name localstack \
        -p 4566:4566 \
        -e PERSISTENCE=1 \
        -e SERVICES=s3,ec2,rds,iam,vpc \
        -v ~/localstack-data:/var/lib/localstack \
        localstack/localstack > /dev/null
    
    # Attendre que LocalStack soit healthy
    echo -n "   Attente de LocalStack (max 60s)..."
    for i in {1..30}; do
        if docker ps --filter "name=localstack" --filter "health=healthy" | grep -q localstack; then
            echo ""
            success "LocalStack démarré et healthy"
            break
        fi
        sleep 2
        echo -n "."
    done
    echo ""
fi

echo ""
fi

# ============================================
# ÉTAPE 3 : Création du cluster Kind
# ============================================
step "[3/10] Création du cluster Kubernetes (Kind)..."

if kind get clusters | grep -q "^idp$"; then
    warning "Cluster 'idp' existe déjà"
else
    kind create cluster --name idp --wait 60s
    success "Cluster Kind 'idp' créé"
fi

# Vérifier que le cluster est accessible
kubectl cluster-info > /dev/null
success "Cluster accessible"

echo ""

# ============================================
# ÉTAPE 4 : Installation de Crossplane
# ============================================
step "[4/10] Installation de Crossplane v1.17.1..."

# Ajouter le repo Helm
helm repo add crossplane-stable https://charts.crossplane.io/stable > /dev/null 2>&1
helm repo update > /dev/null 2>&1
success "Repo Helm ajouté"

# Vérifier si Crossplane est déjà installé
if kubectl get namespace crossplane-system &> /dev/null; then
    warning "Crossplane déjà installé"
else
    # Installer Crossplane
    helm install crossplane crossplane-stable/crossplane \
        --namespace crossplane-system \
        --create-namespace \
        --version 1.17.1 \
        --wait \
        --timeout 5m > /dev/null
    
    success "Crossplane v1.17.1 installé"
fi

# Attendre que les pods soient Running
echo -n "   Attente des pods Crossplane..."
kubectl wait --for=condition=Available deployment/crossplane \
    -n crossplane-system --timeout=300s > /dev/null 2>&1
kubectl wait --for=condition=Available deployment/crossplane-rbac-manager \
    -n crossplane-system --timeout=300s > /dev/null 2>&1
echo ""
success "Crossplane opérationnel"

echo ""

# ============================================
# ÉTAPE 5 : Installation des Providers AWS
# ============================================
step "[5/10] Installation des Providers AWS..."

warning "Cette étape peut prendre 5-15 minutes selon votre connexion"
warning "Si vous êtes sur MTN, assurez-vous que WARP est actif !"

# Vérifier si les providers existent déjà
if kubectl get providers provider-aws-s3 &> /dev/null; then
    warning "Providers déjà installés"
else
    # Appliquer les providers
    kubectl apply -f crossplane/providers/ > /dev/null
    success "Providers soumis"
fi

# Attendre que tous les providers soient HEALTHY
echo -n "   Attente que les providers soient HEALTHY (max 15 min)..."
TIMEOUT=900  # 15 minutes
ELAPSED=0
INTERVAL=10

while [ $ELAPSED -lt $TIMEOUT ]; do
    UNHEALTHY=$(kubectl get providers -o json | jq -r '.items[] | select(.status.conditions[] | select(.type=="Healthy" and .status!="True")) | .metadata.name' | wc -l)
    
    if [ "$UNHEALTHY" -eq 0 ]; then
        echo ""
        success "Tous les providers sont HEALTHY"
        break
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    echo -n "."
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo ""
    error "Timeout : certains providers ne sont pas HEALTHY après 15 min"
fi

echo ""

# ============================================
# ÉTAPE 6 : Configuration des Secrets
# ============================================
step "[6/10] Configuration des secrets AWS..."

if [[ "$MODE" == "local" ]]; then
    if kubectl get secret aws-creds -n crossplane-system &> /dev/null; then
        warning "Secret aws-creds existe déjà"
    else
        kubectl create secret generic aws-creds \
            -n crossplane-system \
            --from-literal='creds=[default]
aws_access_key_id = test
aws_secret_access_key = test' > /dev/null

        success "Secret aws-creds créé (LocalStack)"
    fi
else
    if kubectl get secret aws-creds -n crossplane-system &> /dev/null; then
        success "Secret aws-creds trouvé (AWS réel)"
    else
        error "Mode AWS réel : le secret aws-creds est requis dans crossplane-system. Crée-le avant de relancer (voir README.md / QUICKSTART.md)."
    fi
fi

echo ""

# ============================================
# ÉTAPE 7 : Configuration du ProviderConfig
# ============================================
step "[7/10] Configuration du ProviderConfig..."

if [[ "$MODE" == "local" ]]; then
    kubectl apply -f platform/crossplane/provider-config.yaml > /dev/null
    success "ProviderConfig appliqué (LocalStack)"
else
    kubectl apply -f platform/crossplane/provider-config-aws.yaml > /dev/null
    success "ProviderConfig appliqué (AWS réel)"
fi

echo ""

# ============================================
# ÉTAPE 8 : Configuration RBAC
# ============================================
step "[8/10] Configuration des permissions RBAC..."

kubectl apply -f platform/rbac/ > /dev/null
success "ClusterRoles et ClusterRoleBindings créés"

# Redémarrer les providers pour charger les nouvelles permissions
echo -n "   Redémarrage des providers..."
kubectl delete pods -n crossplane-system -l pkg.crossplane.io/provider --force --grace-period=0 > /dev/null 2>&1
sleep 10
echo ""
success "Providers redémarrés avec nouvelles permissions"

echo ""

# ============================================
# ÉTAPE 9 : Déploiement XRD et Composition
# ============================================
step "[9/10] Déploiement XRD et Composition..."

# Appliquer le XRD
kubectl apply -f crossplane/xrds/xzimbra.yaml > /dev/null
success "XRD Zimbra créé"

# Appliquer les Compositions
kubectl apply -f crossplane/compositions/zimbra-platform-local.yaml > /dev/null
kubectl apply -f crossplane/compositions/zimbra-platform-aws.yaml > /dev/null
success "Compositions (local + aws) créées"

# ConfigMap OpenTelemetry (utilisée par la composition locale)
if [[ "$MODE" == "local" ]]; then
    kubectl apply -f platform/crossplane/otel-collector-config.yaml > /dev/null
    success "ConfigMap OpenTelemetry appliquée"
fi

echo ""

# ============================================
# ÉTAPE 10 : Vérification finale
# ============================================
step "[10/10] Vérification finale..."

# Vérifier les providers
PROVIDERS=$(kubectl get providers --no-headers | wc -l)
HEALTHY_PROVIDERS=$(kubectl get providers -o json | jq -r '[.items[] | select(.status.conditions[] | select(.type=="Healthy" and .status=="True"))] | length')
success "Providers : $HEALTHY_PROVIDERS/$PROVIDERS HEALTHY"

# Vérifier les XRDs
XRDS=$(kubectl get xrd --no-headers | wc -l)
success "XRDs : $XRDS installé(s)"

# Vérifier les Compositions
COMPS=$(kubectl get compositions --no-headers | wc -l)
success "Compositions : $COMPS installée(s)"

echo ""
echo "=================================================="
echo -e "  ${GREEN}✓ Installation terminée avec succès !${NC}"
echo "=================================================="
echo ""
echo "📝 Prochaines étapes :"
echo ""
echo "1. Créer votre premier environnement Zimbra :"
if [[ "$MODE" == "local" ]]; then
    echo "   kubectl apply -f claims/dev-zimbra-local.yaml"
else
    echo "   kubectl apply -f claims/dev-zimbra.yaml"
fi
echo ""
echo "2. Surveiller la création :"
echo "   kubectl get zimbra,bucket,vpc,subnet -w"
echo ""
echo "3. Vérifier les ressources dans LocalStack :"
echo "   export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test"
echo "   aws --endpoint-url=http://localhost:4566 s3 ls"
echo "   aws --endpoint-url=http://localhost:4566 ec2 describe-vpcs"
echo ""
echo "📚 Documentation : README.md"
echo "🔧 Troubleshooting : QUICKSTART.md"
echo ""
echo "=================================================="
