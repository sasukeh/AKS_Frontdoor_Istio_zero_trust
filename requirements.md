# 要件定義書

## 1. プロジェクト概要

### 1.1 目的
Azure Front Door、Istio Service Mesh、Azure Kubernetes Service (AKS)を組み合わせたセキュアなマイクロサービスアーキテクチャのリファレンス実装を提供する。

### 1.2 対象者
- Azureクラウドアーキテクト
- DevOpsエンジニア
- Kubernetesエンジニア
- セキュリティエンジニア

## 2. 機能要件

### 2.1 インフラストラクチャ要件

#### 2.1.1 Azure Front Door
- **機能**: グローバルロードバランサーとしてのHTTP/HTTPSトラフィック配信
- **セキュリティ**: WAF (Web Application Firewall) 機能による脅威防御
- **可用性**: 複数リージョンでの高可用性
- **プライベート接続**: Private Link経由でのAKSアクセス

#### 2.1.2 Azure Kubernetes Service (AKS)
- **Kubernetesバージョン**: 1.28以上
- **ノード構成**: 
  - システムノードプール: Standard_D2s_v3 (最小2台)
  - ユーザーノードプール: Standard_D4s_v3 (最小3台)
- **ネットワーク**: Azure CNI
- **セキュリティ**: 
  - Private Cluster (API Serverへのプライベートアクセス)
  - Azure Active Directory統合
  - Pod Security Standards適用

#### 2.1.3 Istio Service Mesh
- **バージョン**: Istio 1.26.2 (セルフマネージド)
- **インストール方法**: istioctl operatorを使用
- **機能**:
  - サービス間通信のmTLS暗号化
  - トラフィック管理 (Canary deployments, Circuit breaker)
  - 可観測性 (メトリクス、ログ、トレーシング)
  - セキュリティポリシー (Authorization policies)
- **Ingress Gateway**: カスタム設定によるPrivate Link Service統合

#### 2.1.4 なぜセルフマネージドIstioを選択したのか？

##### AKS Managed Istio vs セルフマネージド比較

| 項目 | **AKS Managed Istio** | **セルフマネージド Istio** ✅ |
|---|---|---|
| **管理負荷** | 低い（Azureが管理） | 高い（手動管理必要） |
| **設定柔軟性** | 制限あり | 完全自由 |
| **Private Link統合** | 制限・困難 | カスタム設定可能 |
| **バージョン制御** | Azure依存 | 自由選択 |
| **デバッグ** | 制限あり | 完全アクセス |
| **学習価値** | 低い | 高い |

##### このプロジェクトでセルフマネージドを選択した理由

**1. アーキテクチャ要件**
- **Private Link Service統合**: 特殊なLoadBalancer annotations設定が必要
- **カスタムGateway設定**: Front Door → PLS → Istio の複雑な接続パターン
- **詳細セキュリティ設定**: 企業レベルの認可ポリシー実装

**2. 学習・実装価値**
- **完全理解**: Istioの内部動作とベストプラクティス習得
- **実運用対応**: エンタープライズ環境での実装パターン
- **移植性**: AWS EKS、GKE等でも同様実装可能

**3. 技術的制御**
- **バージョン固定**: Istio 1.26.2 での動作保証
- **設定透明性**: 全設定ファイルの詳細把握
- **トラブルシューティング**: 問題発生時の完全制御

**4. 将来への対応**
- **マルチクラウド対応**: Azure以外でも活用可能
- **カスタマイズ**: 個別要件への柔軟対応
- **アップグレード戦略**: 計画的なバージョンアップ

##### トレードオフ

**❌ デメリット:**
- 手動でのIstioアップグレード・保守が必要
- セキュリティパッチの手動適用
- 運用ノウハウの蓄積が必要

**✅ メリット:**
- 完全な設定制御とカスタマイズ
- 高度なアーキテクチャパターンの実現
- エンタープライズレベルの実装学習

##### 推奨用途

**セルフマネージドIstio (このプロジェクト):**
- エンタープライズアーキテクチャの学習
- 高度なカスタマイズが必要なプロジェクト
- マルチクラウド対応が必要
- 完全制御が必要な本番環境

**AKS Managed Istio:**
- 迅速なプロトタイプ開発
- 管理負荷を抑えたい小規模プロジェクト
- 標準的な設定で十分な場合

### 2.2 アプリケーション要件

#### 2.2.1 サンプルアプリケーション
- **フロントエンド**: Nginx ベースのWebアプリケーション
- **バックエンド**: Node.js/Python ベースのAPIサービス
- **データベース**: PostgreSQL または Redis (オプション)

#### 2.2.2 サービス構成
```yaml
services:
  - name: frontend-service
    type: ClusterIP
    port: 80
  - name: backend-api
    type: ClusterIP
    port: 3000
  - name: database
    type: ClusterIP
    port: 5432
```

## 3. 非機能要件

### 3.1 セキュリティ要件

#### 3.1.1 ネットワークセキュリティ
- **Zero Trust**: 全ての通信はデフォルトで拒否
- **Private Networking**: インターネットからの直接アクセス禁止
- **セグメンテーション**: マイクロサービス間の適切なネットワーク分離

#### 3.1.2 認証・認可
- **Azure AD統合**: AKSクラスターアクセス制御
- **Istio Authorization**: サービス間アクセス制御
- **RBAC**: Kubernetes Role-Based Access Control

#### 3.1.3 暗号化
- **転送時暗号化**: TLS 1.2以上
- **サービス間通信**: Istio mTLS
- **保存時暗号化**: Azure Disk暗号化

### 3.2 パフォーマンス要件
- **レスポンス時間**: 95%ile < 500ms
- **スループット**: 1000 RPS対応
- **可用性**: 99.9%以上

### 3.3 監視・運用要件
- **メトリクス**: Prometheus + Grafana
- **ログ**: Azure Monitor / ELK Stack
- **トレーシング**: Jaeger
- **アラート**: Azure Monitor Alerts

## 4. 技術要件

### 4.1 デプロイメント要件
- **Infrastructure as Code**: Terraform
- **CI/CD**: GitHub Actions または Azure DevOps
- **コンテナレジストリ**: Azure Container Registry
- **自動化**: ワンクリックデプロイメント

### 4.2 開発・運用ツール
- **Terraform**: >= 1.0
- **kubectl**: 最新安定版
- **Azure CLI**: >= 2.50
- **Helm**: >= 3.0
- **istioctl**: Istioバージョンに対応

## 5. 制約事項

### 5.1 技術制約
- セルフマネージドIstio 1.26.2を使用（AKS Managed Istioは使用しない）
- Azure Front Door Premiumのみサポート（Standard版は対象外）
- 単一リージョンでの展開（マルチリージョンは将来対応）
- Istio Operator による管理（Helmチャートは使用しない）

### 5.2 コスト制約
- 開発・テスト環境での利用を想定
- 本番環境での利用は別途コスト最適化が必要

## 6. 検証項目

### 6.1 機能検証
- [ ] Azure Front DoorからAKSサービスへの疎通確認
- [ ] Private Endpoint経由でのアクセス確認
- [ ] Istio Ingress Gatewayの動作確認
- [ ] サービス間通信のmTLS確認

### 6.2 セキュリティ検証
- [ ] インターネットからAKSへの直接アクセス拒否確認
- [ ] WAFによる攻撃遮断確認
- [ ] Network Security Groupの設定確認
- [ ] Istio Authorization Policyの動作確認

### 6.3 パフォーマンス検証
- [ ] 負荷テストによるスループット確認
- [ ] レスポンス時間測定
- [ ] スケーリング動作確認

## 7. リスク分析

### 7.1 技術リスク
- **セルフマネージドIstio**: アップグレードとメンテナンスの手動管理が必要
- **Private Endpoint**: 接続設定の複雑さによる設定ミスのリスク
- **Terraform**: Azure Provider更新による非互換性
- **Istio設定**: 複雑なネットワーク設定による誤設定リスク

### 7.2 運用リスク
- **デプロイメント時間**: 初回デプロイに30-45分程度要する
- **トラブルシューティング**: 複数サービス連携による問題切り分けの困難さ

## 8. 成功基準

### 8.1 機能面
- 全ての検証項目が正常に動作すること
- ドキュメント通りにデプロイメントが完了すること
- サンプルアプリケーションが期待通りに動作すること

### 8.2 運用面
- 自動デプロイメントが30分以内に完了すること
- クリーンアップが正常に実行されること
- トラブルシューティングガイドが有効であること
