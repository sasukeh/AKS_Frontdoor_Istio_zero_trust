# デプロイメントガイド

## 概要

このガイドでは、Azure Front Door + Istio + AKSアーキテクチャの詳細なデプロイメント手順を説明します。

## ⚠️ 重要な事前注意事項

### 実装済み問題の回避策
1. **Private Link Service接続の手動承認が必須**
2. **AKS Node Taintに対応したIstio設定が必要**  
3. **Terraform Location変数の明示的指定が必要**
4. **Load Balancer Frontend IP Configurationの自動生成パターン理解が必要**

詳細は `.prompt.md` の「実装時の重要発見事項とノウハウ」セクションを参照してください。

## 前提条件

### 必要なツール

1. **Azure CLI** (バージョン 2.50以上)

   **macOS:**
   ```bash
   # Homebrew経由
   brew install azure-cli
   
   # インストール確認
   az --version
   ```

   **Windows:**
   ```powershell
   # Winget経由（推奨）
   winget install Microsoft.AzureCLI
   
   # Chocolatey経由
   choco install azure-cli
   
   # または、MSI インストーラーをダウンロード
   # https://aka.ms/installazurecliwindows
   
   # インストール確認
   az --version
   ```

   **Linux (Ubuntu/Debian):**
   ```bash
   # Microsoft リポジトリ追加
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   
   # インストール確認
   az --version
   ```

2. **Terraform** (バージョン 1.0以上)

   **macOS:**
   ```bash
   # Homebrew経由
   brew install terraform
   
   # インストール確認
   terraform --version
   ```

   **Windows:**
   ```powershell
   # Winget経由（推奨）
   winget install Hashicorp.Terraform
   
   # Chocolatey経由
   choco install terraform
   
   # または、手動インストール
   # 1. https://www.terraform.io/downloads.html からダウンロード
   # 2. terraform.exe をPATHの通ったディレクトリに配置
   
   # インストール確認
   terraform --version
   ```

   **Linux:**
   ```bash
   # 公式リポジトリから最新版をダウンロード
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   
   # インストール確認
   terraform --version
   ```

3. **kubectl** (最新安定版)

   **macOS:**
   ```bash
   # Homebrew経由
   brew install kubectl
   
   # インストール確認
   kubectl version --client
   ```

   **Windows:**
   ```powershell
   # Winget経由（推奨）
   winget install Kubernetes.kubectl
   
   # Chocolatey経由
   choco install kubernetes-cli
   
   # または、手動インストール
   # curl.exe -LO "https://dl.k8s.io/release/v1.28.0/bin/windows/amd64/kubectl.exe"
   
   # インストール確認
   kubectl version --client
   ```

   **Linux:**
   ```bash
   # 最新安定版をダウンロード
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   
   # インストール確認
   kubectl version --client
   ```

4. **jq** (JSONパーサー)

   **macOS:**
   ```bash
   # Homebrew経由
   brew install jq
   ```

   **Windows:**
   ```powershell
   # Winget経由（推奨）
   winget install jqlang.jq
   
   # Chocolatey経由
   choco install jq
   
   # または、手動インストール
   # https://github.com/stedolan/jq/releases からダウンロード
   ```

   **Linux (Ubuntu/Debian):**
   ```bash
   # パッケージマネージャー経由
   sudo apt-get update
   sudo apt-get install jq
   ```

5. **Git** (バージョン管理)

   **macOS:**
   ```bash
   # Xcode Command Line Tools (通常は既にインストール済み)
   xcode-select --install
   
   # または Homebrew経由
   brew install git
   ```

   **Windows:**
   ```powershell
   # Winget経由（推奨）
   winget install Git.Git
   
   # Git for Windows をダウンロード・インストール
   # https://git-scm.com/download/win
   
   # または Chocolatey経由
   choco install git
   ```

   **Linux:**
   ```bash
   # Ubuntu/Debian
   sudo apt-get install git
   
   # CentOS/RHEL
   sudo yum install git
   ```

### Azure権限

デプロイメントには以下のAzure権限が必要です：

- **サブスクリプション共同作成者** または以下の組み合わせ：
  - リソースグループの作成・削除権限
  - ネットワーク関連リソースの管理権限
  - AKSクラスターの作成・管理権限
  - Azure Front Doorの作成・管理権限
  - Log Analyticsワークスペースの作成権限

### プラットフォーム固有の設定

#### Windows固有の設定

**PowerShell実行ポリシー:**
```powershell
# 現在の実行ポリシーを確認
Get-ExecutionPolicy

# スクリプト実行を許可（必要に応じて）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**文字エンコーディング:**
```powershell
# UTF-8エンコーディングを設定
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding
```

**改行コード対応:**
```bash
# Git設定（Windows環境での改行コード自動変換）
git config --global core.autocrlf true
```

#### macOS/Linux固有の設定

**実行権限:**
```bash
# スクリプトに実行権限を付与
chmod +x scripts/*.sh
```

**シェル設定:**
```bash
# bashプロファイルまたはzshプロファイルに環境変数を追加
echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
# または
echo 'export PATH=$PATH:/usr/local/bin' >> ~/.zshrc
```

## ステップ1: リポジトリの準備

### 1.1 リポジトリクローン
```bash
git clone git@github.com:sasukeh/AKS_Frontdoor_Istio_zero_trust.git
cd AKS_Frontdoor_Istio_zero_trust
```

### 1.2 環境変数の設定

**macOS/Linux:**
```bash
# 環境変数ファイルをコピー
cp .env.example .env

# .envファイルを編集
nano .env
# または
vim .env
```

**Windows:**
```powershell
# 環境変数ファイルをコピー
Copy-Item .env.example .env

# .envファイルを編集
notepad .env
# または
code .env  # Visual Studio Code使用時
```

### 必須設定項目
```bash
# Azure認証情報
AZURE_SUBSCRIPTION_ID="your-subscription-id"
AZURE_TENANT_ID="your-tenant-id"          # オプション
AZURE_CLIENT_ID="your-client-id"          # サービスプリンシパル使用時
AZURE_CLIENT_SECRET="your-client-secret"  # サービスプリンシパル使用時

# リソース設定
RESOURCE_GROUP_NAME="rg-frontdoor-istio-demo"
LOCATION="japaneast"
ENVIRONMENT="dev"

# AKS設定
AKS_CLUSTER_NAME="aks-frontdoor-istio"
AKS_NODE_COUNT=3
AKS_NODE_VM_SIZE="Standard_D4s_v3"
```

## ステップ2: Azureへのログイン

### 2.1 対話的ログイン
```bash
az login
```

### 2.2 サブスクリプション設定
```bash
# サブスクリプション一覧表示
az account list --output table

# 使用するサブスクリプションを設定
az account set --subscription "your-subscription-id"
```

### 2.3 サービスプリンシパル使用時
```bash
az login --service-principal \
    --username $AZURE_CLIENT_ID \
    --password $AZURE_CLIENT_SECRET \
    --tenant $AZURE_TENANT_ID
```

## ステップ3: デプロイメント実行

### 3.1 自動デプロイメント（推奨）

**macOS/Linux:**
```bash
./scripts/deploy.sh
```

**Windows (PowerShell):**
```powershell
# PowerShell 実行ポリシーの確認・設定
Get-ExecutionPolicy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# スクリプト実行
./scripts/deploy.sh
# または
bash ./scripts/deploy.sh
```

**Windows (Git Bash):**
```bash
./scripts/deploy.sh
```

### 3.2 手動デプロイメント

#### 3.2.1 Terraformによるインフラストラクチャ構築
```bash
cd terraform

# Terraform初期化
terraform init

# プランの確認
terraform plan

# デプロイメント実行
terraform apply
```

#### 3.2.2 AKSクラスターへの接続
```bash
# kubeconfig取得
az aks get-credentials \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $AKS_CLUSTER_NAME

# 接続確認
kubectl get nodes
```

#### 3.2.3 Istioの確認
```bash
# Istio関連ポッドの確認
kubectl get pods -n istio-system

# Istio Gateway確認
kubectl get svc -n istio-system istio-ingressgateway
```

#### 3.2.4 アプリケーションデプロイ
```bash
# アプリケーションデプロイ
kubectl apply -f kubernetes/applications/

# Istio設定適用
kubectl apply -f kubernetes/istio/

# デプロイメント確認
kubectl get pods
kubectl get svc
```

## ステップ4: 疎通確認

### 4.1 自動テスト

**macOS/Linux:**
```bash
./scripts/test-connectivity.sh
```

**Windows (PowerShell):**
```powershell
./scripts/test-connectivity.sh
# または
bash ./scripts/test-connectivity.sh
```

### 4.2 手動テスト

#### 4.2.1 Front Door URL取得

**macOS/Linux:**
```bash
cd terraform
FRONTDOOR_URL=$(terraform output -raw connection_info | jq -r '.frontdoor_url')
echo "Front Door URL: $FRONTDOOR_URL"
```

**Windows (PowerShell):**
```powershell
cd terraform
$FRONTDOOR_URL = terraform output -raw connection_info | jq -r '.frontdoor_url'
Write-Host "Front Door URL: $FRONTDOOR_URL"
```

#### 4.2.2 疎通テスト

**macOS/Linux:**
```bash
# フロントエンドテスト
curl -L $FRONTDOOR_URL

# APIテスト
curl -L $FRONTDOOR_URL/api

# ヘルスチェック
curl -L $FRONTDOOR_URL/health
```

**Windows (PowerShell):**
```powershell
# フロントエンドテスト
Invoke-WebRequest -Uri $FRONTDOOR_URL -UseBasicParsing

# APIテスト
Invoke-WebRequest -Uri "$FRONTDOOR_URL/api" -UseBasicParsing

# ヘルスチェック
Invoke-WebRequest -Uri "$FRONTDOOR_URL/health" -UseBasicParsing

# または curl が利用可能な場合
curl -L $FRONTDOOR_URL
curl -L $FRONTDOOR_URL/api
curl -L $FRONTDOOR_URL/health
```

#### 4.2.3 Istio直接アクセステスト
```bash
# Istio Gateway IP取得
ISTIO_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 直接アクセステスト
curl http://$ISTIO_IP
curl http://$ISTIO_IP/api
```

## ステップ5: 監視とログ

### 5.1 Kubernetesリソース監視
```bash
# ポッド状態確認
kubectl get pods --all-namespaces

# サービス確認
kubectl get svc --all-namespaces

# イベント確認
kubectl get events --sort-by='.lastTimestamp'
```

### 5.2 Istioメトリクス
```bash
# Istio設定確認
kubectl get gateway
kubectl get virtualservice
kubectl get destinationrule

# mTLS状態確認
kubectl get peerauthentication -A
```

### 5.3 ログ確認
```bash
# アプリケーションログ
kubectl logs -l app=frontend
kubectl logs -l app=backend

# Istio Gatewayログ
kubectl logs -n istio-system -l app=istio-ingressgateway

# Istio Proxyログ（サイドカー）
kubectl logs <pod-name> -c istio-proxy
```

## トラブルシューティング

### よくある問題

#### 1. AKSクラスターアクセスエラー
```bash
# 問題: kubectl接続エラー
# 解決策: kubeconfig再取得
az aks get-credentials --resource-group $RESOURCE_GROUP_NAME --name $AKS_CLUSTER_NAME --overwrite-existing
```

#### 2. Istio Gatewayが起動しない
```bash
# 確認コマンド
kubectl describe pod -n istio-system -l app=istio-ingressgateway

# ログ確認
kubectl logs -n istio-system -l app=istio-ingressgateway
```

#### 3. Front Doorから疎通できない
```bash
# Private Endpoint設定確認
az network private-endpoint list --resource-group $RESOURCE_GROUP_NAME

# Network Security Group確認
az network nsg rule list --resource-group $RESOURCE_GROUP_NAME --nsg-name nsg-snet-aks
```

#### 4. mTLSエラー
```bash
# PeerAuthentication確認
kubectl get peerauthentication -A

# TLS設定確認
kubectl get destinationrule -o yaml
```

## パフォーマンス最適化

### 1. リソース調整
```yaml
# HorizontalPodAutoscaler設定例
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: frontend-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: frontend
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### 2. Istio最適化
```yaml
# DestinationRule接続プール設定例
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: frontend-dr
spec:
  host: frontend
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 50
        maxRequestsPerConnection: 10
```

## セキュリティ考慮事項

### 1. ネットワークセキュリティ
- Private Endpointによる内部通信
- Network Security Groupによるアクセス制御
- Istio mTLSによるサービス間暗号化

### 2. 認証・認可
- Azure AD統合
- Istio Authorization Policy
- Kubernetes RBAC

### 3. 監査ログ

**macOS/Linux:**
```bash
# Azure Activity Log確認
az monitor activity-log list --max-events 50

# Kubernetes監査ログ
kubectl get events --sort-by='.lastTimestamp'
```

**Windows (PowerShell):**
```powershell
# Azure Activity Log確認
az monitor activity-log list --max-events 50

# Kubernetes監査ログ
kubectl get events --sort-by='.lastTimestamp'
```

## 本番環境への適用

### 1. 環境分離

**環境別設定ファイル:**
```
.env.dev      # 開発環境
.env.staging  # ステージング環境
.env.prod     # 本番環境
```

**環境変数の読み込み (PowerShell):**
```powershell
# 環境に応じて設定ファイルを読み込み
$env:ENVIRONMENT = "prod"
Get-Content ".env.$env:ENVIRONMENT" | ForEach-Object {
    if ($_ -match "^([^=]+)=(.*)$") {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
    }
}
```

**環境変数の読み込み (Bash):**
```bash
# 環境に応じて設定ファイルを読み込み
export ENVIRONMENT=prod
set -a
source .env.$ENVIRONMENT
set +a
```

### 2. CI/CD統合
- GitHub Actions
- Azure DevOps
- GitLab CI/CD

### 3. 追加考慮事項
- バックアップ戦略
- 災害復旧計画
- セキュリティスキャン
- コスト最適化
