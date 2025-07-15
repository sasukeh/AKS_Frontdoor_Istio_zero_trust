# セキュリティ考慮事項

このドキュメントでは、Azure Front Door + Private Link Service + Istio Gateway アーキテクチャにおけるセキュリティ考慮事項について詳しく説明します。

## 🛡️ ゼロトラストアーキテクチャの実装

### 1. ネットワークセグメンテーション

#### 完全プライベートAKSクラスター
```text
✅ 実装済み: AKS API Serverへのパブリックアクセスなし
✅ 実装済み: プライベートエンドポイント経由のみアクセス
✅ 実装済み: Azure CNIによる詳細なネットワーク制御
```

#### サブネット分離
```text
VNet: 10.0.0.0/16
├── AKS Subnet: 10.0.1.0/24
│   └── Pod CIDR: 10.0.1.0/24
├── Private Endpoint Subnet: 10.0.2.0/24
│   └── Private Link Service用
└── 管理サブネット: 10.0.3.0/24 (将来用)
```

### 2. トラフィック暗号化

#### エンドツーエンドTLS
- **Front Door → PLS**: TLS 1.2/1.3
- **PLS → Istio Gateway**: TLS終端・再暗号化
- **Istio Gateway → Pods**: mTLS (Mutual TLS)
- **Pod間通信**: mTLS自動化

#### 証明書管理
```yaml
# Istio Gateway TLS設定例
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: frontend-gateway
spec:
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: frontend-tls-secret
```

## 🔒 アクセス制御

### 1. Istio認可ポリシー

#### サービス間アクセス制御
```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: frontend-policy
  namespace: default
spec:
  selector:
    matchLabels:
      app: frontend
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/istio-system/sa/istio-ingressgateway-service-account"]
  - to:
    - operation:
        methods: ["GET", "POST"]
```

#### デフォルト拒否ポリシー
```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: default
spec: {}  # 空のspecでデフォルト拒否
```

### 2. Azure RBAC統合

#### AKS管理者アクセス
```bash
# Azure AD グループベースのアクセス制御
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --enable-aad \
  --aad-admin-group-object-ids $AAD_GROUP_ID
```

## 🚨 WAF (Web Application Firewall) 設定

### 1. Azure Front Door WAFポリシー

#### OWASP Top 10対応
```json
{
  "properties": {
    "policySettings": {
      "enabledState": "Enabled",
      "mode": "Prevention"
    },
    "managedRules": {
      "managedRuleSets": [
        {
          "ruleSetType": "Microsoft_DefaultRuleSet",
          "ruleSetVersion": "2.1"
        },
        {
          "ruleSetType": "Microsoft_BotManagerRuleSet",
          "ruleSetVersion": "1.0"
        }
      ]
    }
  }
}
```

#### カスタムルール例
```json
{
  "name": "BlockSQLInjection",
  "priority": 100,
  "enabledState": "Enabled",
  "ruleType": "MatchRule",
  "matchConditions": [
    {
      "matchVariable": "QueryString",
      "operator": "Contains",
      "matchValue": ["' or 1=1", "union select", "drop table"]
    }
  ],
  "action": "Block"
}
```

### 2. レート制限

#### Front Doorレート制限
```json
{
  "name": "RateLimitRule",
  "priority": 200,
  "enabledState": "Enabled",
  "ruleType": "RateLimitRule",
  "rateLimitDurationInMinutes": 1,
  "rateLimitThreshold": 100,
  "action": "Block"
}
```

#### Istio レート制限
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: filter-ratelimit
  namespace: istio-system
spec:
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: SIDECAR_INBOUND
      listener:
        filterChain:
          filter:
            name: "envoy.filters.network.http_connection_manager"
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.local_ratelimit
        typed_config:
          "@type": type.googleapis.com/udpa.type.v1.TypedStruct
          type_url: type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
          value:
            stat_prefix: local_rate_limiter
            token_bucket:
              max_tokens: 100
              tokens_per_fill: 100
              fill_interval: 60s
```

## 🔐 シークレット管理

### 1. Azure Key Vault統合

#### CSI Driver設定
```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-keyvault
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityClientID: "${CLIENT_ID}"
    keyvaultName: "${KEY_VAULT_NAME}"
    objects: |
      array:
        - |
          objectName: frontend-tls-cert
          objectType: secret
          objectVersion: ""
    tenantId: "${TENANT_ID}"
```

### 2. Pod Identity

#### ワークロードアイデンティティ
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: frontend-sa
  namespace: default
  annotations:
    azure.workload.identity/client-id: "${CLIENT_ID}"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  template:
    metadata:
      labels:
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: frontend-sa
```

## 📊 監視・ログ

### 1. セキュリティ監視

#### Azure Sentinelアラート
```kql
// 異常なトラフィックパターンの検出
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
| where action_s == "Block"
| summarize count() by clientIP_s, bin(TimeGenerated, 5m)
| where count_ > 50
```

#### Istio アクセスログ
```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: istio-control-plane
spec:
  meshConfig:
    accessLogFile: "/dev/stdout"
    accessLogFormat: |
      {
        "timestamp": "%START_TIME%",
        "method": "%REQ(:METHOD)%",
        "path": "%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%",
        "protocol": "%PROTOCOL%",
        "response_code": "%RESPONSE_CODE%",
        "response_flags": "%RESPONSE_FLAGS%",
        "bytes_received": "%BYTES_RECEIVED%",
        "bytes_sent": "%BYTES_SENT%",
        "duration": "%DURATION%",
        "upstream_service_time": "%RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)%",
        "x_forwarded_for": "%REQ(X-FORWARDED-FOR)%",
        "user_agent": "%REQ(USER-AGENT)%",
        "request_id": "%REQ(X-REQUEST-ID)%"
      }
```

### 2. コンプライアンス

#### ログ保持ポリシー
- **Azure Monitor**: 30日間（標準）、最大2年間
- **Application Insights**: 90日間（標準）
- **Key Vault監査**: 長期保持（コンプライアンス要件に応じて）

## ⚠️ セキュリティベストプラクティス

### 1. 定期的なセキュリティタスク

#### 週次タスク
- [ ] WAFブロックログの確認
- [ ] 異常なアクセスパターンの調査
- [ ] Istio証明書の期限確認

#### 月次タスク
- [ ] セキュリティパッチの適用
- [ ] アクセス権限の見直し
- [ ] ペネトレーションテスト

#### 四半期タスク
- [ ] セキュリティアーキテクチャレビュー
- [ ] インシデント対応訓練
- [ ] コンプライアンス監査

### 2. セキュリティ設定チェックリスト

#### インフラストラクチャ
- [ ] AKS APIサーバーがプライベートのみ
- [ ] すべてのサブネットにNSGが適用済み
- [ ] Key Vaultアクセスポリシーが最小権限
- [ ] Azure Monitor/Log Analyticsが有効

#### アプリケーション
- [ ] Istio mTLSが有効
- [ ] 認可ポリシーが設定済み
- [ ] シークレットがKey Vaultから取得
- [ ] セキュリティコンテキストが制限的

#### 監視
- [ ] WAFアラートが設定済み
- [ ] 異常検知ルールが有効
- [ ] ログ転送が正常動作
- [ ] ダッシュボードが最新

## 🚨 インシデント対応

### 1. セキュリティインシデント分類

#### レベル1（低）
- WAFによるブロック
- 認証失敗の増加
- **対応**: 監視継続、ログ確認

#### レベル2（中）
- 異常なトラフィックパターン
- 権限昇格の試行
- **対応**: 詳細調査、一時的制限

#### レベル3（高）
- データ漏洩の疑い
- システム侵害の可能性
- **対応**: インシデント対応チーム召集、システム隔離

### 2. 復旧手順

#### 緊急時のアクセス遮断
```bash
# Front Door WAFで全トラフィックブロック
az afd waf-policy update \
  --name MyWAFPolicy \
  --resource-group MyResourceGroup \
  --policy-mode Prevention

# Istio Gateway停止
kubectl scale deployment istio-ingressgateway -n istio-system --replicas=0
```

#### システム復旧
```bash
# 1. セキュリティパッチ適用
kubectl apply -f security-patches/

# 2. 証明書更新
kubectl create secret tls frontend-tls-secret \
  --cert=path/to/new/cert.pem \
  --key=path/to/new/key.pem

# 3. サービス再起動
kubectl rollout restart deployment/frontend deployment/backend
```

## 📚 参考資料

### セキュリティフレームワーク
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [Azure Security Benchmark](https://docs.microsoft.com/en-us/security/benchmark/azure/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

### コンプライアンス
- [Azure SOC 2 Type II](https://docs.microsoft.com/en-us/azure/compliance/offerings/offering-soc-2-type-2)
- [ISO 27001](https://docs.microsoft.com/en-us/azure/compliance/offerings/offering-iso-27001)
- [PCI DSS](https://docs.microsoft.com/en-us/azure/compliance/offerings/offering-pci-dss)

---

🔒 **セキュリティは継続的なプロセスです。定期的な見直しと改善を行ってください。**
