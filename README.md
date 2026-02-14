# IDP Zimbra AWS - Internal Developer Platform

Une plateforme en libre-service permettant aux administrateurs Zimbra de déployer automatiquement une infrastructure AWS complète pour Zimbra Collaboration Suite.

## 🎯 Vision du Projet

**Objectif** : Transformer le déploiement d'infrastructure Zimbra de 2 semaines de travail manuel en **1 fichier YAML + 10 minutes d'attente**.

### Avant l'IDP
- ⏰ 2 semaines de délai
- 👥 5 équipes impliquées (infra, réseau, sécurité, DB, compute)
- 🔧 Connaissance AWS/Terraform requise
- ❌ Erreurs de configuration fréquentes
- 🔑 Gestion manuelle des credentials

### Avec l'IDP
- ⏱️ 10 minutes d'attente
- 👤 1 admin Zimbra autonome
- 📝 Un simple fichier YAML
- ✅ Configuration standardisée et testée
- 🔐 Credentials auto-générés et injectés

---

## 🏗️ Architecture

### Stack Technologique

| Composant | Version | Rôle |
|-----------|---------|------|
| **Crossplane** | v1.17.1 | Orchestrateur d'infrastructure |
| **Kubernetes** | kind (local) | Plateforme de déploiement |
| **LocalStack** | latest | Simulation AWS en local (test) |
| **Providers AWS** | v1.15.0 | Gestion ressources S3, EC2, IAM, RDS |

### Infrastructure Créée (Phase 1 - POC)
```
┌─────────────────────────────────────────────────────────┐
│                      VPC 10.0.0.0/16                    │
│                                                         │
│  ┌────────────────────┐      ┌────────────────────┐   │
│  │  Subnet Public     │      │  Subnet Privé      │   │
│  │  10.0.1.0/24       │      │  10.0.2.0/24       │   │
│  │                    │      │                    │   │
│  │  ┌──────────────┐  │      │  ┌──────────────┐  │   │
│  │  │ EC2 Zimbra   │  │      │  │ RDS MySQL    │  │   │
│  │  │ (À venir)    │  │      │  │ (À venir)    │  │   │
│  │  └──────────────┘  │      │  └──────────────┘  │   │
│  └────────────────────┘      └────────────────────┘   │
│           │                                            │
│    Internet Gateway                                    │
└──────────────┬─────────────────────────────────────────┘
               │
        ┌──────┴──────┐
        │  S3 Bucket  │
        │   Backups   │
        └─────────────┘
```

### Ressources Actuellement Fonctionnelles

- ✅ **VPC** avec DNS activé
- ✅ **2 Subnets** (public + privé)
- ✅ **Internet Gateway**
- ✅ **Route Tables** configurées
- ✅ **S3 Bucket** avec tags personnalisés
- ⏳ **IAM Roles** (à venir)
- ⏳ **RDS Database** (à venir)
- ⏳ **EC2 Instance** (à venir)

---

## 🚀 Installation et Configuration

### Prérequis

#### Logiciels Requis
```bash
# Docker
docker --version  # >= 20.x

# Kind (Kubernetes in Docker)
kind version  # >= 0.20.x

# kubectl
kubectl version --client  # >= 1.28.x

# Helm
helm version  # >= 3.x

# AWS CLI (pour tests LocalStack)
aws --version  # >= 2.x

# LocalStack
docker pull localstack/localstack
```

#### VPN/Proxy (Important !)
⚠️ **Si vous utilisez MTN ou un FAI qui bloque CloudFront** :
```bash
# Installer Cloudflare WARP
# Instructions : https://developers.cloudflare.com/warp-client/get-started/linux/

# Activer WARP avant l'installation des providers
warp-cli registration new
warp-cli connect
```

---

### Installation Pas-à-Pas

#### 1. Démarrer LocalStack avec Persistance
```bash
# Créer le dossier de persistance
mkdir -p ~/localstack-data

# Lancer LocalStack
docker run -d \
  --name localstack \
  -p 4566:4566 \
  -e PERSISTENCE=1 \
  -e SERVICES=s3,ec2,rds,iam,vpc \
  -v ~/localstack-data:/var/lib/localstack \
  localstack/localstack

# Vérifier que LocalStack est healthy
docker ps | grep localstack
```

#### 2. Créer le Cluster Kind
```bash
# Créer le cluster
kind create cluster --name idp

# Vérifier
kubectl cluster-info
```

#### 3. Installer Crossplane v1.17.1
```bash
# Ajouter le repo Helm
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

# Installer Crossplane
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --create-namespace \
  --version 1.17.1 \
  --wait

# Vérifier l'installation
kubectl get pods -n crossplane-system
```

#### 4. Installer les Providers AWS
```bash
cd ~/Documents/idp-zimbra-aws

# Activer WARP si nécessaire
warp-cli status

# Appliquer les providers
kubectl apply -f crossplane/providers/

# Surveiller l'installation (5-10 minutes)
kubectl get providers -w
# Attendre que tous soient HEALTHY=True
```

#### 5. Configurer les Secrets et ProviderConfig
```bash
# Créer le secret AWS (credentials fictives pour LocalStack)
kubectl create secret generic aws-creds \
  -n crossplane-system \
  --from-literal=creds='[default]
aws_access_key_id = test
aws_secret_access_key = test'

# Appliquer le ProviderConfig
kubectl apply -f platform/crossplane/provider-config.yaml

# Vérifier
kubectl get providerconfig
kubectl get secret aws-creds -n crossplane-system
```

#### 6. Configurer les Permissions RBAC
```bash
# Appliquer les ClusterRoles et Bindings
kubectl apply -f platform/rbac/

# Vérifier
kubectl get clusterrole | grep providerconfig
kubectl get clusterrolebinding | grep provider-aws
```

#### 7. Créer le CRD ProviderConfigUsage
```bash
# Créer le CRD manquant (workaround pour compatibilité)
kubectl apply -f platform/rbac/providerconfigusage-crd.yaml

# Vérifier
kubectl get crd providerconfigusages.aws.upbound.io
```

#### 8. Déployer l'XRD et la Composition
```bash
# Créer l'XRD Zimbra
kubectl apply -f crossplane/xrds/xzimbra.yaml

# Vérifier
kubectl get xrd

# Créer la Composition
kubectl apply -f crossplane/compositions/zimbra-platform.yaml

# Vérifier
kubectl get composition
```

---

## 💻 Utilisation

### Créer une Instance Zimbra

#### 1. Créer le fichier Claim
```bash
# Créer un dossier pour les claims
mkdir -p claims

# Créer le claim
cat <<YAML > claims/dev-zimbra.yaml
apiVersion: idp.example.com/v1alpha1
kind: Zimbra
metadata:
  name: dev-zimbra-001
spec:
  environment: dev
  region: us-east-1
  storageSizeGB: 50
  databaseStorageGB: 20
  instanceType: t3.medium
  enableBackups: true
YAML
```

#### 2. Appliquer le Claim
```bash
# Déployer l'infrastructure
kubectl apply -f claims/dev-zimbra.yaml

# Surveiller la création
kubectl get zimbra,xzimbra,bucket,vpc,subnet -w
```

#### 3. Vérifier l'État
```bash
# Voir le status du Claim
kubectl get zimbra dev-zimbra-001

# Détails complets
kubectl describe zimbra dev-zimbra-001

# Voir toutes les ressources créées
kubectl get bucket,vpc,subnet,internetgateway,routetable
```

#### 4. Vérifier dans LocalStack
```bash
# Configurer AWS CLI pour LocalStack
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# Lister les buckets S3
aws --endpoint-url=http://localhost:4566 s3 ls

# Voir les VPCs
aws --endpoint-url=http://localhost:4566 ec2 describe-vpcs \
  --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

---

## 🔧 Troubleshooting

### Problème : Providers ne passent pas HEALTHY

**Symptôme** :
```bash
kubectl get providers
# HEALTHY=False après 10+ minutes
```

**Solutions** :
1. Vérifier les logs :
```bash
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3
```

2. Si erreur réseau/CloudFront :
```bash
# Activer WARP
warp-cli connect
warp-cli status

# Redémarrer les providers
kubectl delete pods -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3
```

---

### Problème : Ressources en SYNCED=False

**Symptôme** :
```bash
kubectl get bucket
# SYNCED=False READY=False
```

**Diagnostic** :
```bash
# Voir l'erreur exacte
kubectl describe bucket <bucket-name>

# Logs du provider
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3
```

**Solutions courantes** :

1. **Erreur "forbidden" (RBAC)** :
```bash
# Vérifier les permissions
kubectl get clusterrolebinding | grep provider-aws

# Réappliquer les RBAC
kubectl apply -f platform/rbac/

# Redémarrer les providers
kubectl delete pods -n crossplane-system -l pkg.crossplane.io/provider
```

2. **Erreur "ProviderConfigUsage not found"** :
```bash
# Vérifier le CRD
kubectl get crd providerconfigusages.aws.upbound.io

# Si absent, créer
kubectl apply -f platform/rbac/providerconfigusage-crd.yaml
```

3. **LocalStack non accessible** :
```bash
# Vérifier LocalStack
docker ps | grep localstack

# Redémarrer si nécessaire
docker restart localstack

# Vérifier l'endpoint dans ProviderConfig
kubectl get providerconfig default -o yaml | grep endpoint
```

---

### Problème : AWS CLI ne peut pas accéder à LocalStack

**Symptôme** :
```bash
aws --endpoint-url=http://localhost:4566 s3 ls
# Unable to locate credentials
```

**Solution** :
```bash
# Configurer des credentials fictives
aws configure set aws_access_key_id test
aws configure set aws_secret_access_key test
aws configure set region us-east-1

# Ou via variables d'environnement
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

---

## 📊 État Actuel du Projet

### ✅ Fonctionnel (Phase 1 - POC)

| Composant | Status | Notes |
|-----------|--------|-------|
| Crossplane v1.17.1 | ✅ | Stable |
| Providers AWS (s3, ec2, iam, rds) | ✅ | HEALTHY |
| LocalStack | ✅ | Avec persistance |
| XRD Zimbra | ✅ | API définie |
| Composition S3+VPC | ✅ | Fonctionne |
| Claims Zimbra | ✅ | Crée les ressources |
| RBAC Permissions | ✅ | Corrigées |
| S3 Buckets | ✅ | SYNCED + READY |
| VPC + Networking | ✅ | SYNCED + READY |

### ⏳ À Compléter (Phase 2)

| Composant | Priorité | Estimation |
|-----------|----------|------------|
| IAM Roles + Policies | 🔴 Haute | 2h |
| RDS Database (MySQL) | 🔴 Haute | 2h |
| EC2 Instance Ubuntu | 🔴 Haute | 3h |
| Security Groups | 🟡 Moyenne | 1h |
| User-data script Zimbra | 🟡 Moyenne | 2h |
| Status enrichi (IPs, endpoints) | 🟢 Basse | 1h |
| Documentation admin | 🟢 Basse | 2h |

---

## 🔮 Roadmap

### Phase 2 : Infrastructure Complète (En cours)
- [ ] Ajouter IAM Roles à la Composition
- [ ] Ajouter RDS Database
- [ ] Ajouter EC2 Instance
- [ ] Tester end-to-end sur LocalStack

### Phase 3 : Production-Ready
- [ ] Tester sur AWS réel (Free Tier)
- [ ] Ajouter monitoring (Prometheus/Grafana)
- [ ] Implémenter backup automation
- [ ] Documentation admin finale

### Phase 4 : Features Avancées
- [ ] Multi-région support
- [ ] High Availability (Multi-AZ)
- [ ] Auto-scaling
- [ ] Disaster Recovery

---

## 📁 Structure du Projet
```
idp-zimbra-aws/
├── README.md                       # Cette documentation
├── backup/                         # Backups des ressources
│   ├── composition-backup.yaml
│   ├── providers-backup.yaml
│   └── xrd-backup.yaml
├── claims/                         # Claims utilisateur
│   └── dev-zimbra.yaml            # Exemple de claim
├── crossplane/
│   ├── compositions/              # Compositions Crossplane
│   │   └── zimbra-platform.yaml
│   ├── providers/                 # Définitions des providers
│   │   ├── provider-aws-ec2.yaml
│   │   ├── provider-aws-iam.yaml
│   │   ├── provider-aws-rds.yaml
│   │   └── provider-aws-s3.yaml
│   └── xrds/                     # XRDs (API definitions)
│       └── xzimbra.yaml
├── infrastructure/               # Ressources standalone (test)
│   ├── s3-bucket.yaml
│   └── vpc.yaml
├── platform/
│   ├── crossplane/
│   │   └── provider-config.yaml  # Configuration LocalStack
│   └── rbac/                     # Permissions RBAC
│       ├── provider-providerconfig-access.yaml
│       ├── provider-s3-binding.yaml
│       ├── provider-ec2-binding.yaml
│       ├── provider-iam-binding.yaml
│       ├── provider-rds-binding.yaml
│       └── providerconfigusage-crd.yaml
└── scripts/                      # Scripts utilitaires
    └── setup.sh                  # Setup complet (à créer)
```

---

## 🤝 Contribution

### Debugging Réalisé

Ce projet a nécessité la résolution de multiples challenges :

1. **Blocage réseau MTN** → Solution : Cloudflare WARP
2. **Incompatibilité Crossplane v2 mode Pipeline** → Downgrade v1.17.1
3. **Permissions RBAC manquantes** → Création ClusterRoles manuels
4. **CRD ProviderConfigUsage absent** → Création manuelle
5. **Provider-family-aws en conflit** → Utilisation providers modulaires uniquement

### Leçons Apprises

- Les providers modulaires Upbound v1.15 ont des incompatibilités avec Crossplane v1.17
- Le CRD `ProviderConfigUsage` est requis mais absent en v1.17
- Les permissions RBAC ne sont pas auto-créées par le rbac-manager
- LocalStack nécessite `s3_use_path_style: true` dans le ProviderCn développement (IAM + RDS + EC2)
