# sample-app — sample-app v0.1.0 分析
> 日期：2026-09-25
> render 參數：無（未傳 -f / -s / -n，全部用 chart 預設 values；namespace 未指定）
> 圖檔路徑：`diagrams/sample-app.png`（SVG：`diagrams/sample-app.svg`）
> rendered YAML：`rendered/sample-app-rendered.yaml`
> 產生方式：`./bin/chart-diagram ./charts/sample-app`（helm lint 通過，僅 INFO「icon is recommended」；kube-diagrams 警告 IngressClass 'nginx' undefined —— 無 cluster 時的正常現象，見 §7）

## 1. 架構總覽

這是一個單 workload 的教學用 Helm Chart（`Chart.yaml` description：「教學用 Helm Chart：單 workload + Ingress + Service + ConfigMap + PVC + HPA」）。分四層：

1. **入口層**：Ingress `sample-app-sample-app`（host `sample-app.local`，path `/` Prefix，`ingressClassName: nginx`）→
2. **服務層**：ClusterIP Service `sample-app-sample-app`（port 80 → targetPort 80）→
3. **工作負載層**：Deployment `sample-app-sample-app`（2 副本，`nginx:1.27`，由 HPA 管理 2–5 副本）→
4. **輔助物件**：ConfigMap（透過 `envFrom` 注入 GREETING/LOG_LEVEL）、PVC（掛到 `/usr/share/nginx/html`）、ServiceAccount（非 default）。

所有物件共用同一組 `app.kubernetes.io/*` labels（由 `_helpers.tpl` 的 `sample-app.labels` 定義），KubeDiagrams 據此把 7 個物件分組在同一個 Application 框內（見 PNG 圖）。所有物件都位於 namespace `default`（manifests 中沒有 Namespace 物件，`default` 是 KubeDiagrams 的預設假設，見 §7）。

## 2. Mental Model

（依 bootstrap §12 形式；`→` = configuration-derived relationship，不代表真實 runtime traffic）

```text
                         External Client
                               │
                               ▼
              [ Ingress: sample-app-sample-app ]
        host=sample-app.local  path=/ (Prefix)
        ingressClassName=nginx
                               │
                         HTTP routing（推導）
                               │
                               ▼
              [ Service: sample-app-sample-app ]
                 port 80 → targetPort 80
                               │
          selector: app.kubernetes.io/name=sample-app,
                    app.kubernetes.io/instance=sample-app
                    （推導：與 pod template labels 一致）
                    ┌─────────┴─────────┐
                    ▼                   ▼
             [ sample-app Pod ]   [ sample-app Pod ]
             nginx:1.27           (replicas: 2)
                    │
    envFrom: ConfigMap (GREETING, LOG_LEVEL)
    volume: PVC → /usr/share/nginx/html
                    │
                    ▼
       [ PVC: sample-app-sample-app ]
          ReadWriteOnce, 1Gi
```

側邊配置關係（不出現在主流量鏈上）：

```text
[ HPA: sample-app-sample-app ] ──scaleTargetRef──▶ [ Deployment ] ──▶ Pods
[ ServiceAccount: sample-app-sample-app ] ◀──serviceAccountName── [ Pod spec ]
[ ConfigMap: sample-app-sample-app ] ◀──envFrom.configMapRef── [ container spec ]
```

## 3. Resource 清單

| kind | name | 作用 | 配置事實（出處：rendered/sample-app-rendered.yaml） |
|---|---|---|---|
| ServiceAccount | sample-app-sample-app | Pod 使用的身份（非 default） | `serviceAccountName: sample-app-sample-app`（Deployment）；無任何 Role/RoleBinding 在 manifests 中 |
| ConfigMap | sample-app-sample-app | 應用設定 | `data: GREETING="Hello from sample-app"`, `LOG_LEVEL="info"`；經 `envFrom.configMapRef` 注入 container |
| PersistentVolumeClaim | sample-app-sample-app | 持久化存儲 | `accessModes: [ReadWriteOnce]`，`storage: 1Gi`，無 `storageClassName`（`values.yaml persistence.storageClass: ""`） |
| Service | sample-app-sample-app | 集群內路由 | `type: ClusterIP`，`port: 80 / targetPort: 80`，`selector: {app.kubernetes.io/name: sample-app, app.kubernetes.io/instance: sample-app}` |
| Deployment | sample-app-sample-app | 工作負載 | `replicas: 2`，image `nginx:1.27`（IfNotPresent），`containerPort: 80`，limits 250m/128Mi、requests 100m/64Mi，volume `data` 掛到 `/usr/share/nginx/html`；無 probes、無 securityContext |
| HorizontalPodAutoscaler | sample-app-sample-app | 自動縮放 | `scaleTargetRef` → Deployment `sample-app-sample-app`；`minReplicas: 2 / maxReplicas: 5`；CPU Utilization 70% |
| Ingress | sample-app-sample-app | 外部入口 | `ingressClassName: nginx`，host `sample-app.local`，path `/` Prefix，backend `sample-app-sample-app:80`；無 `tls` block |

## 4. 流量路徑

```text
External Client
  → Ingress sample-app-sample-app          （推導關係：Ingress.spec.rules[0].host + backend service name/port）
    host: sample-app.local, path: / (Prefix)
  → Service sample-app-sample-app:80       （推導關係：Ingress backend.service.name == Service.metadata.name；port 80 == Service.spec.ports[0].port）
    port 80 → targetPort 80
  → Pods（Deployment sample-app-sample-app）（推導關係：Service.spec.selector 與 Deployment.spec.template.metadata.labels 逐 key 相同）
```

- **推導關係 1（Ingress → Service）**：`Ingress.spec.rules[0].http.paths[0].backend.service.name = sample-app-sample-app`、`port.number = 80`（rendered 行 172–176）與 `Service.metadata.name = sample-app-sample-app`、`spec.ports[0].port = 80`（rendered 行 55、68–71）完全對應。
- **推導關係 2（Service → Pods）**：`Service.spec.selector = {app.kubernetes.io/name: sample-app, app.kubernetes.io/instance: sample-app}`（rendered 行 65–67）與 `Deployment.spec.template.metadata.labels`（rendered 行 94–96）逐 key 相同；`Deployment.spec.selector.matchLabels` 也是同一組（行 89–91）。從 configuration 看，該 Deployment 的 2 個 Pod 理論上會成為 endpoints（實際 endpoints 是否存在無法從 manifests 確定，見 §7）。
- 集群內部沒有其他 Service，ConfigMap/env 中也沒有出現任何 service DNS 名稱或 URL，因此**沒有** Service A → Service B 的內部依賴（Step 6 結論）。
- Ingress 依賴 `IngressClass 'nginx'`，該 IngressClass 是否存在於 cluster **無法從 manifests 確定**（kube-diagrams 已給出 undefined 警告）。

## 5. 優點

| ✓ 項目 | 理由 |
|---|---|
| Image tag 固定 | `nginx:1.27`（`values.yaml image.tag: "1.27"`），非 `latest`/無 tag，可重現部署 |
| Resources 完整且支撐 HPA | requests（100m/64Mi）與 limits（250m/128Mi）都有（`values.yaml resources`）；CPU limit 存在，HPA 的 CPU Utilization metric 才有計算基準（bootstrap §649–667） |
| 標準 labels + selector 一致 | 所有物件帶 `app.kubernetes.io/*` 標準 labels（`_helpers.tpl`）；Deployment selector 與 pod labels、Service selector 都來自同一個 `sample-app.selectorLabels` helper，rendered YAML 中逐 key 驗證一致 |
| 專用 ServiceAccount | `serviceAccountName: sample-app-sample-app`（`deployment.yaml`），不用 default SA，符合最小化慣例 |
| Config/Secrets 乾淨 | ConfigMap 只有非敏感的 `GREETING`/`LOG_LEVEL`，無敏感值 inline；`envFrom` 來源明確（單一 `configMapRef`） |
| Helm hygiene 完整 | 條件渲染（`ingress.enabled`/`persistence.enabled`/`autoscaling.enabled`）、有 `NOTES.txt`、`appVersion: "1.27"` 已填、values 全部有預設且可覆寫 |
| Service type 合理 | `ClusterIP`（`values.yaml service.type`），僅集群內暴露 + Ingress 入口，沒有多餘的 LoadBalancer/NodePort 暴露 |

## 6. 缺點與風險

| 嚴重度 | 項目 | 出處檔案 | 風險 | 建議改法（不代改） |
|---|---|---|---|---|
| 高 | PVC `ReadWriteOnce` 與 `replicas: 2`（及 HPA max 5）衝突 | `templates/pvc.yaml`（accessModes）、`values.yaml`（replicaCount, autoscaling.maxReplicas） | RWO 的 PV 只能被單一節點掛載；第 2 個（及 HPA 擴容出的）Pod 若排到不同節點將無法掛載 `/usr/share/nginx/html`，HPA 的實際可擴容量被存儲卡住（實際排程結果屬運行事實，見 §7） | nginx 的 html 是唯讀靜態內容：把 `pvc.yaml` accessMode 改為 `ReadOnlyMany`（需後端存儲支援），或設 `persistence.enabled: false` |
| 中 | 完全沒有 probes（liveness/readiness/startup） | `templates/deployment.yaml`（rendered Deployment 無 probe 欄位） | kubelet 無法驗證 nginx 健康； hung 的 container 會繼續被 Service 路由流量，重啟機制也缺失 | 在 `deployment.yaml` container 加 liveness/readiness（如 `tcpSocket: {port: 80}` 或 GET `/`，port 與 Service targetPort 80 一致） |
| 中 | Ingress 無 TLS | `templates/ingress.yaml`（spec 無 `tls` block） | `sample-app.local` 的流量明文傳輸 | 在 `ingress.yaml` 加 `spec.tls` 並指定憑證來源（或改用 cluster 級憑證管理） |
| 中 | 無 securityContext（runAsNonRoot / readOnlyRootFilesystem / capabilities.drop 皆無） | `templates/deployment.yaml`（pod 與 container 層皆無） | 容器以 image 預設權限運行，缺乏硬化的容器被入侵時影響範圍較大（具體預設行為屬運行事實，見 §7） | 在 `deployment.yaml` 加 pod 級 `securityContext`（runAsNonRoot、runAsUser、readOnlyRootFilesystem、capabilities.drop: [ALL]） |
| 低 | 無 NetworkPolicy | 無對應 template | Pod 之間無顯式隔離，是否安全取決於 cluster 是否有 default-deny（無法確定，見 §7） | 新增 `templates/networkpolicy.yaml`（條件渲染）或明確依賴 cluster 級策略 |
| 低 | `image.repository: nginx` 未含 registry 前綴 | `values.yaml` | image 來源隱式指向 Docker Hub，air-gapped/registry mirror 環境需額外處理 | `values.yaml` 改為完整路徑（如 `registry.example.com/app/nginx`） |
| 低 | Chart 無 icon | `Chart.yaml`（helm lint INFO：icon is recommended） | 純外觀，無功能影響 | `Chart.yaml` 加 `icon`（可選） |

## 7. 無法確定（運行事實）

以下問題需要上 cluster 才知道，本報告一律不猜：

1. **Pod 狀態**：`replicas: 2` 只是 configuration；Pod 是否實際啟動、是否 Ready 無法確定。
2. **Service endpoints**：selector 對得上只表示「理論上」會產生 endpoints（bootstrap §646）；實際 endpoints 是否建立、是否為 0，無法確定。
3. **IngressClass 是否存在**：kube-diagrams 警告 `IngressClass 'nginx' undefined`；`ingressClassName: nginx` 能否解析成實際路由，取決於 cluster 中是否有該 IngressClass 及對應 controller，無法確定。
4. **Ingress 路由/TLS 是否生效**：host `sample-app.local` 的 DNS 是否解析、流量是否真的經過 Ingress，均屬運行事實。
5. **PVC 是否 bound**：`pvc.yaml` 只宣告 claim；是否有 PV 被綁定、RWO 是否導致多節點掛載問題，無法確定。
6. **HPA 是否實際縮放**：HPA 只表示「configuration 允許 scale」（bootstrap §663–667）；是否真的在 2–5 之間變動，無法確定。
7. **env 注入結果**：`envFrom` 是 configuration；container 內是否真的有 `GREETING`/`LOG_LEVEL` 變數，無法確定。
8. **SA 的 API 權限**：manifests 中沒有 Role/RoleBinding/ClusterRole，`sample-app-sample-app` SA 實際能對 K8s API 做什麼，無法確定。
9. **NetworkPolicy 現況**：cluster 層是否有 default-deny 策略，無法確定。
10. **namespace**：rendered manifests 中沒有 Namespace 物件；圖上的 `default` 是 KubeDiagrams 的預設假設，實際部署到哪個 namespace 取決於安裝參數（本次 render 未傳 `-n`）。

---
*分析依 `skills/helm-chart-analyzer/SKILL.md` 工作流程 + `k8s-helm-learning-bootstrap.md` §11 十個 step（Inventory → 分組 → workload 關係 → Service routing → Ingress/external → internal traffic → Storage → Configuration → HPA/scaling → Security/RBAC）與 §12 圖式。每句皆標註 配置事實 / 推導關係 / 運行事實（無法確定）類別。*
