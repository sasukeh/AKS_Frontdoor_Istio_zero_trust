# トラブルシューティングガイド

## 概要

このドキュメントでは、Azure Front Door + Istio + AKSアーキテクチャでよく発生する問題とその解決方法について説明します。

## 🆕 2025年7月: 実装で発見された重要な問題と解決策

### Critical Problem 1: Front Door 404エラー（Private Link Service接続未承認）

**症状**: 
- Front Doorエンドポイントへのアクセスで404 Not Foundが返される
- インフラストラクチャは正常にデプロイされている
- AKS内部からのアクセスは成功する

**根本原因**: 
Front DoorからPrivate Link Serviceへの接続が自動承認されず、Pending状態になっている

**診断コマンド**:
```bash
# Private Link Service接続状況確認
az network private-link-service show -g <resource-group> -n <pls-name> \
  --query "privateEndpointConnections[].privateLinkServiceConnectionState" --output table

# 期待される結果: Status が "Approved"
# 問題がある場合: Status が "Pending"
```

**解決方法**:
```bash
# 1. 接続の詳細情報取得
az network private-link-service show -g <resource-group> -n <pls-name> \
  --query "privateEndpointConnections[].{name:name,status:privateLinkServiceConnectionState.status}" --output table

# 2. 各接続を手動承認（すべてのPending接続に対して実行）
az network private-link-service connection update \
  -g <resource-group> \
  --service-name <pls-name> \
  --name <connection-name> \
  --connection-status Approved \
  --description "Approved Front Door connection"

# 3. 承認後1-2分待ってからテスト
curl -k https://<frontdoor-endpoint>
```

### Critical Problem 2: Istio Pods Pending（Node Taint未対応）

**症状**:
- `kubectl get pods -n istio-system` でPodがPending状態
- Events に `0/2 nodes are available: 2 node(s) had untolerated taints`

**根本原因**:
AKSノードプールのTaint設定にIstio Podsが対応していない

**診断コマンド**:
```bash
# ノードのTaint確認
kubectl describe nodes | grep -A5 Taints

# Istio Podの状態確認
kubectl describe pod -n istio-system <istio-pod-name>
```

**解決方法**:
Istio設定ファイル（`istio-install-config-fixed.yaml`）に適切なtolerationを追加:
```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  components:
    pilot:
      k8s:
        tolerations:
          - key: "workload"
            operator: "Equal"
            value: "user" 
            effect: "NoSchedule"
          - key: "CriticalAddonsOnly"
            operator: "Equal"
            value: "true"
            effect: "NoSchedule"
        nodeSelector:
          agentpool: user
    ingressGateways:
      - name: istio-ingressgateway
        enabled: true
        k8s:
          tolerations:
            - key: "workload"
              operator: "Equal"
              value: "user"
              effect: "NoSchedule"
            - key: "CriticalAddonsOnly"  
              operator: "Equal"
              value: "true"
              effect: "NoSchedule"
          nodeSelector:
            agentpool: user
```

### Critical Problem 3: Terraform Location Mismatch

**症状**:
```
Error: InvalidResourceReference: Private link service cannot reference frontend ip configuration since it is already referenced
```

**根本原因**:
- 変数のデフォルト値が実際のデプロイ先と異なる
- "Japan East" vs "southeastasia" の不一致

**解決方法**:
```hcl
# terraform/main.tf でlocationを明示的に渡す
module "frontdoor" {
  source = "./modules/frontdoor"
  location = var.location  # この行を追加
  # ...他のパラメータ
}
```

### Critical Problem 4: Load Balancer Frontend IP Configuration 特定

**症状**:
Private Link ServiceでLoad BalancerのfrontendIPConfiguration IDが不明

**解決パターン**:
AKSが生成するフロントエンドIP設定名は以下のパターン:
```
{hash}-{subnet-name}
```

**確認方法**:
```bash
# Load Balancer確認
kubectl get services -n istio-system istio-ingressgateway

# Azure CLIで詳細確認  
az network lb show -g MC_<resource-group>_<cluster-name>_<location> -n kubernetes-internal
```

## デプロイメント関連の問題

### 1. Terraformデプロイメントエラー

#### 1.1 認証エラー
**症状**: `Error: building account: could not acquire access token`

**原因**: Azure認証が適切に設定されていない

**解決策**:
```bash
# Azure CLIでログイン
az login

# サブスクリプション確認
az account show

# 必要に応じてサブスクリプション設定
az account set --subscription "your-subscription-id"
```

#### 1.2 リソース名の重複
**症状**: `A resource with the ID already exists`

**原因**: 既存のリソース名と重複している

**解決策**:
```bash
# .envファイルでリソース名を変更
RESOURCE_GROUP_NAME="rg-frontdoor-istio-demo-$(date +%Y%m%d)"
AKS_CLUSTER_NAME="aks-frontdoor-istio-$(date +%Y%m%d)"
```

#### 1.3 リソース制限エラー
**症状**: `Quota exceeded` または `SKU not available`

**原因**: サブスクリプション制限またはリージョン制限

**解決策**:
```bash
# 利用可能なVMサイズ確認
az vm list-sizes --location japaneast

# クォータ確認
az vm list-usage --location japaneast

# 別のリージョンまたはVMサイズを試行
LOCATION="eastus"
AKS_NODE_VM_SIZE="Standard_D2s_v3"
```

### 2. AKSクラスター接続問題

#### 2.1 kubeconfig取得エラー
**症状**: `ERROR: (AuthorizationFailed)`

**原因**: AKSクラスターへの権限不足

**解決策**:
```bash
# Azure AD権限確認
az role assignment list --assignee $(az account show --query user.name -o tsv)

# AKS管理者権限取得
az aks get-credentials \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $AKS_CLUSTER_NAME \
    --admin
```

#### 2.2 Private Clusterアクセスエラー
**症状**: `Unable to connect to the server`

**原因**: Private ClusterのAPI Serverに外部からアクセスしようとしている

**解決策**:
```bash
# プライベートエンドポイント経由でアクセス
# または、Azure Bastionやジャンプボックスを使用

# 一時的な解決策（開発環境のみ）
az aks update \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $AKS_CLUSTER_NAME \
    --api-server-authorized-ip-ranges $(curl -s ifconfig.me)/32
```

## Istio関連の問題

### 3. Istio Gateway問題

#### 3.1 Istio Gatewayが起動しない
**症状**: `CrashLoopBackOff` または `Pending`

**診断コマンド**:
```bash
# ポッド状態確認
kubectl get pods -n istio-system -l app=istio-ingressgateway

# イベント確認
kubectl describe pod -n istio-system -l app=istio-ingressgateway

# ログ確認
kubectl logs -n istio-system -l app=istio-ingressgateway
```

**一般的な原因と解決策**:

1. **リソース不足**
   ```bash
   # ノードリソース確認
   kubectl top nodes
   kubectl describe nodes
   
   # リソース要求量調整
   kubectl patch deployment istio-ingressgateway -n istio-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"istio-proxy","resources":{"requests":{"cpu":"100m","memory":"128Mi"}}}]}}}}'
   ```

2. **LoadBalancer作成エラー**
   ```bash
   # Service状態確認
   kubectl describe svc istio-ingressgateway -n istio-system
   
   # Azure Load Balancer確認
   az network lb list --resource-group $NODE_RESOURCE_GROUP
   ```

#### 3.2 External IP取得できない
**症状**: `<pending>` 状態が続く

**診断**:
```bash
# Service詳細確認
kubectl describe svc istio-ingressgateway -n istio-system

# Azure Load Balancer確認
NODE_RESOURCE_GROUP=$(az aks show --resource-group $RESOURCE_GROUP_NAME --name $AKS_CLUSTER_NAME --query nodeResourceGroup -o tsv)
az network lb list --resource-group $NODE_RESOURCE_GROUP
```

**解決策**:
```bash
# Internal Load Balancerとして設定
kubectl patch svc istio-ingressgateway -n istio-system -p '{"metadata":{"annotations":{"service.beta.kubernetes.io/azure-load-balancer-internal":"true"}}}'
```

### 4. mTLS認証問題

#### 4.1 サービス間通信エラー
**症状**: `503 Service Unavailable` または connection timeout

**診断**:
```bash
# PeerAuthentication確認
kubectl get peerauthentication -A

# DestinationRule確認
kubectl get destinationrule -A

# Envoy設定確認
kubectl exec -n default <pod-name> -c istio-proxy -- curl localhost:15000/config_dump
```

**解決策**:
```bash
# mTLS設定確認
kubectl describe peerauthentication default -n istio-system

# 必要に応じてmTLSをPermissiveモードに変更
kubectl patch peerauthentication default -n istio-system --type merge -p '{"spec":{"mtls":{"mode":"PERMISSIVE"}}}'
```

## アプリケーション関連の問題

### 5. アプリケーションデプロイエラー

#### 5.1 イメージPullエラー
**症状**: `ImagePullBackOff` または `ErrImagePull`

**診断**:
```bash
kubectl describe pod <pod-name>
kubectl get events --sort-by='.lastTimestamp'
```

**解決策**:
```bash
# パブリックイメージの場合
kubectl patch deployment frontend -p '{"spec":{"template":{"spec":{"containers":[{"name":"frontend","image":"nginx:alpine","imagePullPolicy":"Always"}]}}}}'

# プライベートレジストリの場合
kubectl create secret docker-registry acr-secret \
    --docker-server=<acr-name>.azurecr.io \
    --docker-username=<service-principal-id> \
    --docker-password=<service-principal-password>
```

#### 5.2 Health Check失敗
**症状**: Readiness Probe失敗

**診断**:
```bash
# ポッド詳細確認
kubectl describe pod <pod-name>

# アプリケーションログ確認
kubectl logs <pod-name>

# 手動ヘルスチェック
kubectl exec <pod-name> -- curl localhost:80/health
```

## Front Door関連の問題

### 6. Front Door疎通問題

#### 6.1 502 Bad Gateway
**症状**: Front Door経由でアクセス時に502エラー

**診断手順**:
```bash
# Front Door設定確認
az cdn endpoint show --name $FRONTDOOR_ENDPOINT_NAME --profile-name $FRONTDOOR_PROFILE_NAME --resource-group $RESOURCE_GROUP_NAME

# オリジン状態確認
az cdn origin show --endpoint-name $FRONTDOOR_ENDPOINT_NAME --profile-name $FRONTDOOR_PROFILE_NAME --resource-group $RESOURCE_GROUP_NAME --name aks-origin
```

**一般的な原因**:
1. **Private Endpoint設定ミス**
   ```bash
   # Private Endpoint確認
   az network private-endpoint list --resource-group $RESOURCE_GROUP_NAME
   ```

2. **Certificate問題**
   ```bash
   # TLS設定確認
   az cdn custom-domain show --endpoint-name $FRONTDOOR_ENDPOINT_NAME --profile-name $FRONTDOOR_PROFILE_NAME --resource-group $RESOURCE_GROUP_NAME --name custom-domain
   ```

#### 6.2 WAF Block
**症状**: 403 Forbidden エラー

**診断**:
```bash
# WAFログ確認
az monitor activity-log list --resource-group $RESOURCE_GROUP_NAME --max-events 50

# WAFルール確認
az network front-door waf-policy rule list --policy-name $WAF_POLICY_NAME --resource-group $RESOURCE_GROUP_NAME
```

**解決策**:
```bash
# 一時的にWAFを無効化（テスト用）
az network front-door waf-policy update --name $WAF_POLICY_NAME --resource-group $RESOURCE_GROUP_NAME --mode Detection
```

## パフォーマンス問題

### 7. 応答時間の遅延

#### 7.1 高レイテンシ
**診断**:
```bash
# Istio メトリクス確認
kubectl exec -n istio-system <istio-proxy-pod> -- curl localhost:15000/stats/prometheus

# アプリケーションメトリクス
kubectl top pods
kubectl top nodes
```

**最適化**:
```bash
# Connection Pool設定
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: frontend-dr-optimized
spec:
  host: frontend
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 50
        maxRequestsPerConnection: 10
        h2MaxRequests: 100
EOF
```

### 8. リソース不足

#### 8.1 ノードリソース不足
**症状**: Pods が `Pending` 状態

**診断**:
```bash
kubectl describe node
kubectl top nodes
kubectl get pods --all-namespaces | grep Pending
```

**解決策**:
```bash
# ノードプールスケールアップ
az aks nodepool scale \
    --resource-group $RESOURCE_GROUP_NAME \
    --cluster-name $AKS_CLUSTER_NAME \
    --name user \
    --node-count 5
```

## 緊急時の対応

### 9. 緊急時のトラブルシューティング

#### 9.1 システム全体ダウン
**対応手順**:
1. **現状確認**
   ```bash
   kubectl get pods --all-namespaces
   kubectl get nodes
   kubectl get svc
   ```

2. **ログ収集**
   ```bash
   kubectl logs --previous <pod-name>
   kubectl describe node <node-name>
   ```

3. **緊急復旧**
   ```bash
   # ポッド再起動
   kubectl rollout restart deployment/frontend
   kubectl rollout restart deployment/backend
   
   # Istio Gateway再起動
   kubectl rollout restart deployment/istio-ingressgateway -n istio-system
   ```

#### 9.2 ロールバック手順
```bash
# アプリケーションロールバック
kubectl rollout undo deployment/frontend
kubectl rollout undo deployment/backend

# Istio設定ロールバック
kubectl delete -f kubernetes/istio/
kubectl apply -f kubernetes/istio/previous-config/
```

## ログ収集とデバッグ

### 10. 詳細ログ収集

#### 10.1 包括的なログ収集スクリプト
```bash
#!/bin/bash
# debug-collect.sh

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEBUG_DIR="debug_${TIMESTAMP}"
mkdir -p $DEBUG_DIR

# Kubernetes状態
kubectl get all --all-namespaces > $DEBUG_DIR/k8s_all.txt
kubectl describe nodes > $DEBUG_DIR/nodes_describe.txt
kubectl get events --all-namespaces --sort-by='.lastTimestamp' > $DEBUG_DIR/events.txt

# Istio状態
kubectl get gateway,virtualservice,destinationrule,peerauthentication -A > $DEBUG_DIR/istio_config.txt
kubectl logs -n istio-system -l app=istio-ingressgateway > $DEBUG_DIR/istio_gateway.log

# アプリケーションログ
kubectl logs -l app=frontend > $DEBUG_DIR/frontend.log
kubectl logs -l app=backend > $DEBUG_DIR/backend.log

# Azure リソース状態
az resource list --resource-group $RESOURCE_GROUP_NAME > $DEBUG_DIR/azure_resources.json

echo "Debug information collected in $DEBUG_DIR"
```

## 予防策とベストプラクティス

### 11. 監視設定

#### 11.1 アラート設定
```bash
# Azure Monitor アラート作成例
az monitor metrics alert create \
    --name "AKS CPU High" \
    --resource-group $RESOURCE_GROUP_NAME \
    --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.ContainerService/managedClusters/$AKS_CLUSTER_NAME \
    --condition "avg Percentage CPU > 80" \
    --description "AKS cluster CPU usage is high"
```

#### 11.2 ヘルスチェック強化
```yaml
# 改善されたヘルスチェック例
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

このガイドを参考に、問題の特定と解決を行ってください。さらに詳細な支援が必要な場合は、Azure サポートにお問い合わせください。
