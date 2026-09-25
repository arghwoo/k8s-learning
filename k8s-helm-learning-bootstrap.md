# Kubernetes Helm Chart Learning Sandbox — Bootstrap

> 目標：完全不啟動 Kubernetes cluster，只把 Helm Chart render 成 Kubernetes YAML，再產生 topology / architecture diagram，最後交給本地 LLM 解讀。

## 整體流程

```text
                    ┌──────────────────┐
                    │    Helm Chart    │
                    │                  │
                    │ Chart.yaml       │
                    │ values.yaml      │
                    │ templates/*      │
                    └────────┬─────────┘
                             │
                             │ helm template
                             ▼
                    ┌──────────────────┐
                    │ rendered.yaml    │
                    │                  │
                    │ Kubernetes       │
                    │ manifests       │
                    └────────┬─────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
                ▼                         ▼
       Helm Visualizer             KubeDiagrams
                │                         │
                └────────────┬────────────┘
                             ▼
                    Kubernetes topology
                             │
                             ▼
                     Local LLM analysis
```

本流程**禁止自動建立或連線到 Kubernetes cluster**。

不要執行：

```bash
helm install
helm upgrade
kubectl apply
kubectl create
kubectl delete
```

除非之後明確決定要進入真實 cluster 實驗階段。

---

# 1. 前置需求

需要：

- Helm 3+
- Git（如果 Chart 來自 Git repository）
- Python 3（KubeDiagrams 本地使用時可能需要）
- 瀏覽器
- 一個本地 LLM / Agent

確認 Helm：

```bash
helm version
```

確認：

```bash
helm template --help
```

---

# 2. 準備 Helm Chart

假設 Chart 在：

```text
./my-chart
```

典型結構：

```text
my-chart/
├── Chart.yaml
├── values.yaml
├── charts/
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── configmap.yaml
    └── ...
```

如果 Chart 有 dependencies，先執行：

```bash
helm dependency list ./my-chart
```

必要時：

```bash
helm dependency update ./my-chart
```

這只是下載 Chart dependencies，不會建立 Kubernetes resource。

---

# 3. Render Helm Chart

核心指令：

```bash
helm template my-app ./my-chart
```

建議直接輸出成檔案：

```bash
helm template my-app ./my-chart > rendered.yaml
```

現在會得到：

```text
my-chart/
rendered.yaml
```

`rendered.yaml` 是後續 visualization 與 LLM 分析的主要輸入。

---

# 4. 使用正確的 values

如果 Chart 有不同 environment：

```text
values.yaml
values-dev.yaml
values-prod.yaml
```

例如：

```bash
helm template my-app ./my-chart   -f values.yaml   -f values-dev.yaml   > rendered-dev.yaml
```

如果需要指定參數：

```bash
helm template my-app ./my-chart   -f values.yaml   -f values-dev.yaml   --set image.tag=latest   > rendered-dev.yaml
```

**不要猜 values。**

如果不確定 production/dev 應該使用哪組 values，先詢問使用者。

---

# 5. Render 前先檢查 Chart

執行：

```bash
helm lint ./my-chart
```

如果使用特定 values：

```bash
helm lint ./my-chart   -f values.yaml   -f values-dev.yaml
```

如果 lint 有 warning，可以記錄，但不要擅自修改 Chart。

---

# 6. 快速查看產生了哪些 Kubernetes Objects

Linux/macOS：

```bash
grep "^kind:" rendered.yaml
```

PowerShell：

```powershell
Select-String "^kind:" rendered.yaml
```

也可以搜尋：

```bash
grep "^apiVersion:" rendered.yaml
```

常見結果：

```text
Service
Deployment
ConfigMap
Secret
Ingress
HorizontalPodAutoscaler
ServiceAccount
Role
RoleBinding
NetworkPolicy
PersistentVolumeClaim
```

這一步的目的是先建立第一層 mental model：

> 「這個 Helm Chart 到底建立了哪些 Kubernetes object？」

---

# 7. Visualization Option A — Helm Visualizer

Helm Visualizer：

https://github.com/unrealandychan/Helm-Visualizer

用途：

- 直接理解 Helm Chart
- 不需要 Kubernetes cluster
- 看 rendered resources
- 查看 resources 之間的關係
- 點擊 resource 查看 YAML

優先嘗試直接使用 Helm Chart。

如果工具版本 / UI 要求 rendered YAML，則使用：

```text
rendered.yaml
```

作為輸入。

---

# 8. Visualization Option B — KubeDiagrams

KubeDiagrams：

https://github.com/falkeio/kubediagrams

它可以把 Kubernetes manifests / Helm 等輸入轉成 architecture diagram。

如果使用本地 CLI，依照目前專案 README 安裝，不要自行猜測參數。

核心概念：

```text
Helm Chart
    ↓
helm template
    ↓
rendered.yaml
    ↓
KubeDiagrams
    ↓
Kubernetes architecture diagram
```

Online viewer：

https://kubediagrams.lille.inria.fr/

如果只是第一次測試，可以優先使用 Online KubeDiagrams，不需要安裝任何東西。

---

# 9. 非常重要：Diagram ≠ Runtime Traffic

目前這個流程產生的是：

```text
Kubernetes configuration topology
```

不是：

```text
real runtime traffic
```

也就是：

```text
Ingress
   │
   ▼
Service
   │
   ▼
Deployment
   │
   ▼
Pod
```

代表「從 configuration 推導出的關係」。

它**不代表**：

- Pod 真的存在
- Service 真的有 endpoints
- HTTP request 真的發生
- DNS 真的成功
- NetworkPolicy 真的允許 traffic
- HPA 真的會 scale
- Container 真的 healthy

因此分析時必須區分：

### Configuration fact

例如：

```text
Service selector:
  app: backend
```

### Inferred relationship

例如：

```text
Service → backend Pods
```

### Runtime fact

例如：

```text
Service currently has 3 healthy endpoints
```

在沒有真正 cluster 的情況下，第三種不能假裝存在。

---

# 10. 將結果交給 Local LLM

推薦把以下東西提供給本地模型：

```text
1. Chart.yaml
2. values.yaml
3. 使用中的其他 values files
4. rendered.yaml
5. topology / diagram
```

如果 Chart 很大，可以先只提供：

```text
rendered.yaml
```

再逐步補：

```text
templates/
values/
Chart.yaml
```

---

# 11. 給 Local LLM 的 System / Task Prompt

把下面這段直接交給模型。

---

## Kubernetes Architecture Learning Agent

你是一個 Kubernetes 教學分析助手。

你的任務不是修改 Kubernetes configuration，也不是部署任何 resource。

你的任務是根據：

1. Helm Chart
2. Helm values
3. `helm template` 產生的 rendered Kubernetes manifests
4. topology / architecture diagram

建立一個清楚、可驗證的 Kubernetes mental model。

### 重要限制

- 不得假設存在沒有出現在 manifests 裡的 Kubernetes resource。
- 不得假設真的存在 Kubernetes cluster。
- 不得把 configuration relationship 說成 runtime fact。
- 不得假設 Pod 已經啟動。
- 不得假設 Service 已經有 endpoints。
- 不得假設 network traffic 實際存在。
- 不得假設 DNS、Ingress、NetworkPolicy、HPA 等 runtime behavior 已經成功。
- 如果資料不足，明確說「無法從目前的 manifests 確定」。
- 不要修改 Chart。
- 不要執行 `helm install`、`helm upgrade`、`kubectl apply` 或任何會建立/修改 cluster state 的指令。

---

## 分析順序

### Step 1 — Inventory

先列出所有 Kubernetes objects：

```text
Namespace
Deployment
ReplicaSet
Pod template
Service
Ingress
ConfigMap
Secret
PVC
HPA
ServiceAccount
Role
RoleBinding
NetworkPolicy
...
```

每個 object 說明：

- kind
- name
- namespace
- 用途

---

### Step 2 — Application grouping

嘗試把 objects 按 application / workload 分組。

例如：

```text
Frontend
├── Deployment
├── Service
├── ConfigMap
└── Ingress

Backend
├── Deployment
├── Service
├── Secret
└── HPA
```

如果無法確定 grouping，說明你的推導依據。

---

### Step 3 — Workload relationship

解釋：

```text
Deployment
   ↓
ReplicaSet
   ↓
Pod template
```

以及 labels / selectors 如何建立關係。

特別找：

```yaml
spec:
  selector:
```

與：

```yaml
metadata:
  labels:
```

之間的對應。

---

### Step 4 — Service routing

對每一個 Service 解釋：

```text
Service
  │
  ├── selector
  │
  ▼
matching Pod labels
```

並回答：

1. Service selector 是什麼？
2. 哪些 Pod template labels match？
3. 從 configuration 看，哪些 Pods 理論上會成為 endpoints？
4. 有沒有可能 selector 對不到？
5. Service port / targetPort 是什麼？

不要聲稱實際 endpoints 存在。

---

### Step 5 — Ingress / external traffic

如果有 Ingress，畫出概念流程：

```text
External Client
      │
      ▼
Ingress
      │
      ▼
Service
      │
      ▼
Pods
```

解釋：

- host
- path
- backend Service
- backend port

如果沒有 Ingress，明確說明沒有從目前 manifests 看到 Ingress。

---

### Step 6 — Internal traffic

找出可能的：

```text
Service A → Service B
```

來源包括：

- environment variables
- ConfigMap
- application configuration
- URLs
- Service DNS names
- container args
- command
- known service references

但是要區分：

```text
Configuration indicates dependency
```

與：

```text
Runtime traffic was observed
```

---

### Step 7 — Storage

分析：

```text
Pod
 ↓
volume
 ↓
PVC
 ↓
Storage
```

如果只有 `emptyDir`，解釋它與 PVC 的差異。

---

### Step 8 — Configuration

分析：

```text
ConfigMap
Secret
   ↓
Pod
```

找出：

- env
- envFrom
- volumeMounts
- volumes

說明 configuration 是如何進入 container。

不要顯示 Secret 的實際敏感值。

---

### Step 9 — HPA / scaling

如果有 HPA：

```text
HPA
 │
 ▼
Deployment
 │
 ▼
Pods
```

解釋：

- minReplicas
- maxReplicas
- target metric
- scaleTargetRef

但不要說「它現在正在 scale」。

只能說：

> 「Configuration indicates that HPA is configured to potentially scale this Deployment under the specified metric conditions。」

---

### Step 10 — Security / RBAC

分析：

```text
ServiceAccount
   ↓
Role / ClusterRole
   ↓
RoleBinding / ClusterRoleBinding
```

以及 NetworkPolicy。

指出：

- 哪個 workload 使用哪個 ServiceAccount
- 它可能取得哪些 Kubernetes API permissions
- NetworkPolicy 對哪些 Pod / traffic 建立限制

不要把 RBAC permissions 說成 application runtime 一定會使用。

---

# 12. 最後產生一張「Kubernetes Mental Model」

請用類似下面的形式：

```text
                         External Client
                               │
                               ▼
                          [ Ingress ]
                               │
                         HTTP routing
                               │
                               ▼
                         [ frontend-svc ]
                               │
                         selector=frontend
                               │
                    ┌──────────┴──────────┐
                    ▼                     ▼
              [ frontend Pod ]      [ frontend Pod ]
                    │
                    │ application dependency
                    ▼
                  [ backend-svc ]
                    │
              selector=backend
                    │
              ┌─────┴─────┐
              ▼           ▼
         [backend Pod] [backend Pod]
              │
              ▼
            [PVC]
```

圖中：

- `→` = configuration-derived relationship
- `●` = conceptual request / dependency only
- 不要把它解釋成真實 runtime traffic

---

# 13. 最後列出「值得學的 Kubernetes Concepts」

根據實際 Chart，自動挑選最值得學習的概念。

例如：

```text
Priority learning topics:

1. Deployment vs ReplicaSet vs Pod
2. Service selector
3. ClusterIP / targetPort
4. Ingress routing
5. ConfigMap / Secret injection
6. HPA
7. ServiceAccount / RBAC
8. PVC
9. NetworkPolicy
10. Helm values → Kubernetes manifests
```

不要固定列這十個。

應該根據實際 Chart 出現的 resources 決定。

---

# 14. 建議的學習循環

每拿到一個新的 Helm Chart：

```text
                    ┌───────────────┐
                    │   Helm Chart  │
                    └───────┬───────┘
                            │
                            ▼
                    helm template
                            │
                            ▼
                    rendered.yaml
                            │
                  ┌─────────┴─────────┐
                  ▼                   ▼
           Helm Visualizer       KubeDiagrams
                  │                   │
                  └─────────┬─────────┘
                            ▼
                     看 Architecture
                            │
                            ▼
                     Local LLM
                            │
                            ▼
                  建立 Kubernetes Model
                            │
                            ▼
                  自己提出「為什麼」
                            │
                            ▼
                     再問 Local LLM
```

---

# 15. 第一輪不要追求全部理解

第一次看到大型 production Helm Chart 時，不要試圖一次理解所有 YAML。

先回答：

```text
1. 有哪些 application？
2. 有哪些 Deployment？
3. 有哪些 Service？
4. 哪些 Service 對應哪些 Pods？
5. 外部 request 從哪裡進來？
6. Service 之間可能怎麼連？
7. 哪些 ConfigMap / Secret 被誰使用？
8. 哪些 workload 有 HPA？
9. 哪些 workload 使用 PVC？
10. 有沒有 NetworkPolicy？
```

只要這十個問題能回答，通常已經建立了第一層 cluster mental model。

---

# 16. 安全原則

這個 sandbox 的設計原則是：

```text
Helm Chart
    ↓
helm template
    ↓
Static YAML
    ↓
Visualization
    ↓
LLM analysis
```

而不是：

```text
Helm Chart
    ↓
helm install
    ↓
Kubernetes Cluster
```

因此在這個階段：

**不需要 kubeconfig。**

如果 shell 中存在 production kubeconfig，也不要讓學習 agent 自動使用：

```bash
kubectl config current-context
```

不要讓 agent 執行：

```bash
kubectl apply
kubectl create
kubectl delete
helm install
helm upgrade
helm uninstall
```

---

# 17. 建議目錄

可以建立：

```text
k8s-learning/
├── charts/
│   └── my-chart/
│
├── rendered/
│   └── rendered.yaml
│
├── diagrams/
│   ├── topology.png
│   └── topology.svg
│
└── notes/
    └── architecture.md
```

流程：

```bash
helm template my-app ./charts/my-chart > ./rendered/rendered.yaml
```

然後：

```text
rendered/rendered.yaml
        ↓
Visualizer
        ↓
diagrams/
        ↓
Local LLM
        ↓
notes/architecture.md
```

---

# 18. 最終目標

這套工具鏈不是為了讓你「看懂一張圖」。

真正目標是建立這個 mental model：

```text
Helm
 │
 │ renders
 ▼
Kubernetes Objects
 │
 ├── Workload
 │     └── Deployment
 │           └── ReplicaSet
 │                 └── Pod
 │
 ├── Networking
 │     ├── Service
 │     └── Ingress
 │
 ├── Configuration
 │     ├── ConfigMap
 │     └── Secret
 │
 ├── Storage
 │     └── PVC
 │
 ├── Scaling
 │     └── HPA
 │
 └── Security
       ├── ServiceAccount
       ├── Role
       └── NetworkPolicy
```

以及理解：

```text
External request
       │
       ▼
    Ingress
       │
       ▼
    Service
       │
       ▼
Pod selection
       │
       ▼
    Pod
       │
       ▼
Container
       │
       ├── ConfigMap
       ├── Secret
       └── Storage
```

等你真正理解這張圖，再進入 kind / k3d / minikube 做 runtime 實驗，學習效率會高很多。

---

## Quick Start

如果只是要開始第一次測試：

```bash
# 1. Render
helm template my-app ./my-chart > rendered.yaml

# 2. 檢查 objects
grep "^kind:" rendered.yaml

# 3. 用 Helm Visualizer 或 KubeDiagrams 看 topology

# 4. 把以下資料交給 Local LLM：
#    - Chart.yaml
#    - values.yaml
#    - rendered.yaml
#    - topology screenshot / diagram

# 5. 要求 Local LLM 按照本文件的
#    Kubernetes Architecture Learning Agent
#    規則分析
```

**本 Bootstrap 的核心原則：先理解 configuration，再理解 runtime；先建立 mental model，再啟動真正的 cluster。**
