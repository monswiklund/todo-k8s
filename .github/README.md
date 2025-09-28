# CI/CD Setup Guide

## GitHub Secrets Configuration

För att aktivera CI/CD-pipelinen behöver du konfigurera följande secrets i GitHub:

### Obligatoriska Secrets

| Secret Name | Beskrivning | Exempel |
|-------------|-------------|---------|
| `DOCKER_USERNAME` | Docker Hub användarnamn | `codecrasher2` |
| `DOCKER_PASSWORD` | Docker Hub access token | `dckr_pat_xxx...` |
| `AWS_SSH_PRIVATE_KEY` | SSH private key för EC2-åtkomst | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `ALB_MANAGER_IP` | Manager node IP-adress | `54.83.91.123` |
| `ALB_DNS_NAME` | ALB DNS-namn | `todo-swarm-alb-123456789.eu-west-1.elb.amazonaws.com` |

### Hur du får värden för secrets

1. **DOCKER_USERNAME & DOCKER_PASSWORD**
   ```bash
   # Logga in på Docker Hub → Account Settings → Security → New Access Token
   ```

2. **AWS_SSH_PRIVATE_KEY**
   ```bash
   # Kopiera innehållet i din privata SSH-nyckel
   cat ~/.ssh/id_rsa
   ```

3. **ALB_MANAGER_IP & ALB_DNS_NAME**
   ```bash
   # Efter terraform apply
   cd terraform
   terraform output github_secrets_required
   ```

### Konfigurera secrets i GitHub

1. Gå till ditt GitHub repo
2. Settings → Secrets and variables → Actions
3. Klicka "New repository secret"
4. Lägg till varje secret enligt tabellen ovan

### Deployment Environment

CI/CD-pipelinen använder en `production` environment. Konfigurera detta:

1. Settings → Environments
2. Skapa ny environment: `production`
3. (Valfritt) Aktivera "Required reviewers" för manuell godkännning

## Workflow Triggers

Pipelinen triggas vid:
- Push till `main`/`master` branch
- Pull requests mot `main`/`master`
- Manuell trigger via GitHub Actions UI

## Pipeline Steg

1. **Build & Test** - .NET build och tester
2. **Docker Build** - Multi-arch image build och push
3. **Deploy** - Deployment till AWS Docker Swarm
4. **Health Check** - Verifiering via ALB
5. **Rollback** - Automatisk rollback vid fel

## Monitoring

Efter deployment, övervaka:
- GitHub Actions logs
- ALB health checks i AWS Console
- Docker service logs på manager node