---
name: helm-chart-analyzer
description: 分析某個目錄的 Helm Chart：用 bin/chart-diagram 靜態 render（helm template）+ 產生 topology 圖（KubeDiagrams SVG/PNG），再由 LLM 產出架構講解與優缺點報告，寫入 notes/。純靜態分析，絕不碰 cluster。Use when the user asks to read, explain, visualize, review, or analyze a Helm chart (「分析/講解/畫圖/優缺點」).
---

# Helm Chart Analyzer

給定一個 Helm Chart 目錄 → render + 畫圖 → 講解 + 優缺點 → 報告存 `notes/`。

## 硬性限制（任何情況下都遵守）

- **不啟動 cluster、不使用 kubeconfig、不連任何 K8s API server。**
- 禁止 `helm install` / `helm upgrade` / `helm uninstall` / `kubectl apply` 或任何會修改 cluster state 的指令。
- 只允許：讀檔案、`helm lint`、`helm template`、`bin/chart-diagram`（它只做上面這些）。
- **不修改 chart 檔案**。建議只寫進報告。
- 每句話標記類別，不得混淆：
  - **配置事實**：manifests 裡寫明的事（port、replicas、selector）
  - **推導關係**：由 label/selector/annotation 推出的連結（ingress→svc→pod）
  - **運行事實**：需要 cluster 才能知道（endpoint 存在、Pod 健康、實際流量）→ 本工具**永遠拿不到**，一律寫「無法從目前的 manifests 確定」
- 資料不足時明說「無法確定」，禁止猜。

## 工作流程

### 1. 定位 chart

- 使用者指定目錄 → 直接用；先確認該目錄有 `Chart.yaml`。
- 未指定 → 用 `glob` 找 `charts/**/Chart.yaml`，列出候選問使用者。
- 先讀 `Chart.yaml` 與 `values.yaml`，取得 chart `name`、`version`、`appVersion`（release name 預設用 chart name）。

### 2. 環境檢查

```bash
command -v helm >/dev/null && test -x .venv/bin/kube-diagrams && echo OK
```

- 非 OK → 照 README「環境重設（如果換機器）」一節重建，或請使用者跑；不要假裝能繼續。

### 3. Render + 畫圖

```bash
./bin/chart-diagram <chart-dir> [release-name] [-f extra-values.yaml] [-s k=v] [-n ns]
```

- 使用者给的 values / set / namespace 原樣傳入；沒给就用預設。
- 腳本會輸出 `rendered/<release>-rendered.yaml`、`diagrams/<release>.svg`、`diagrams/<release>.png` 與 rendered kinds 摘要。
- 失敗（lint 之外的 render error、kube-diagrams crash）→ 把原始錯誤回報給使用者並**停止**，不要換 chart、不要吞錯。
- `IngressClass undefined` 這類的 lint INFO 是「無 cluster」的正常現象，不是失敗。

### 4. 讀素材（全部都要讀，缺一不可）

1. `Chart.yaml`、`values.yaml`
2. `templates/` 下**所有** `.yaml`（含 `_helpers.tpl`）
3. `rendered/<release>-rendered.yaml`（完整讀）
4. `diagrams/<release>.png`（讀圖，與 YAML 交叉比對：圖上每個節點都要能在 YAML 找到來源）

### 5. 架構講解

按 `k8s-helm-learning-bootstrap.md` §11「分析順序」的 10 個 step 做（Inventory → 分組 → workload 關係 → Service routing → Ingress/external → internal traffic → Storage → Configuration → HPA/scaling → Security/RBAC）。該節的 prompt 是權威版本，本 skill 只是流程入口。

最後照 bootstrap §12 畫一張文字版「Kubernetes Mental Model」ASCII 圖。

### 6. 優缺點

逐項檢查（標記 ✓ / ✗ / N/A，每項附 YAML 出處）：

| 面向 | 檢查點 |
|---|---|
| Image | tag 固定（非 `latest`/無 tag）？registry 路徑完整？ |
| Resources | requests/limits 都有？CPU/mem 比例合理？ |
| Probes | liveness / readiness / startup？路徑與 port 和 Service 一致？ |
| Security | `runAsNonRoot`、`readOnlyRootFilesystem`、`capabilities.drop`？SA 非 default？ |
| Labels | 用 `app.kubernetes.io/*` 標準 labels？selector 與 labels 一致？ |
| Config/Secrets | 敏感值有沒有 inline 進 ConfigMap？envFrom 來源清楚？ |
| Storage | accessMode 符合使用方式？大小合理？ |
| Scaling | HPA metric 有對應的 resource limit？min/max 合理？ |
| Helm hygiene | 條件渲染？`NOTES.txt`？`appVersion` 有填？values 有預設且可覆寫？ |
- **Namespace 規則**：namespace 只來自 `-n` 參數（未指定 = `default`）。圖上的 `ns` 框是 KubeDiagrams 的**假設**，不是 manifest 內容——除非 chart 本身有 Namespace object，否則「實際部署到哪個 namespace」一律寫進「無法確定」。

每個 ✗ 寫：**風險**（會發生什麼）+ **改法**（改哪個檔哪個 key），但**不代改**。
✓ 也要簡短說明「為什麼算好」。

### 7. 報告

寫入 `notes/<release>-<YYYY-MM-DD>.md`：

```markdown
# <release> — <chart-name> v<chart-version> 分析
> 日期 / render 參數（-f, -s, -n）/ 圖檔路徑

## 1. 架構總覽
（一段話講清楚這是什麼應用、幾層、誰連誰）
## 2. Mental Model
（§12 的 ASCII 圖）
## 3. Resource 清單
（table: kind / name / 作用 / 配置事實）
## 4. 流量路徑
（external → ingress → svc → pod；每條標「推導關係」）
## 5. 優點
（✓ 項目，各一句理由）
## 6. 缺點與風險
（table: 嚴重度 / 項目 / 出處檔案 / 風險 / 建議改法）
## 7. 無法確定（運行事實）
（明確列出哪些問題需要上 cluster 才知道）
```

回覆使用者：3–5 行摘要 + 最重要的一個優缺點 + 報告路徑 + 圖路徑。**不要把整份報告貼進 chat。**

## 驗證（交報告前必做）

1. 圖 vs YAML：rendered YAML 裡每個 workload/Service/Ingress 都出現在圖上（或有解釋：如純 Secret 不出現）。
2. 抽 2 個「推導關係」回 YAML 驗證 selector/labels 真的對得上。
3. 報告裡沒有把「配置」講成「運行」（搜自己寫的文字：「正在運行」「已連上」「實際流量」→ 改掉）。

## 範例

```bash
./bin/chart-diagram ./charts/sample-app
# → rendered/sample-app-rendered.yaml + diagrams/sample-app.png
# → 讀素材 → 分析 → notes/sample-app-2026-09-25.md
```
