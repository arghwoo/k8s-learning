# k8s-learning

Helm Chart → rendered YAML → topology 圖（SVG/PNG）→ 交給 LLM 分析。
完整學習流程見 [k8s-helm-learning-bootstrap.md](k8s-helm-learning-bootstrap.md)。

**原則：不啟動 cluster、不 `helm install`、不 `kubectl apply`。全部是靜態 render。**

## 快速開始

```bash
./bin/chart-diagram ./charts/sample-app
```

產生：

```text
rendered/sample-app-rendered.yaml   # helm template 輸出（之後給 LLM 的主輸入）
diagrams/sample-app.svg             # topology 圖（可編輯、可搜尋）
diagrams/sample-app.png             # 同一張圖的 PNG
```

## 用法

```bash
./bin/chart-diagram <chart-path> [release-name] [options]

  -f, --values FILE     額外 values 檔，可重複（-f values-dev.yaml）
  -s, --set KEY=VALUE   覆寫單一值，可重複（-s image.tag=latest）
  -n, --namespace NS    用 namespace render
  -o, --output-dir DIR  圖輸出目錄（預設 ./diagrams）
      --rendered-dir D  rendered.yaml 輸出目錄（預設 ./rendered）
      --no-png          只產 SVG
      --skip-lint       跳過 helm lint
```

範例：

```bash
./bin/chart-diagram ./charts/my-chart my-app -f values-dev.yaml -s image.tag=latest
```

## 目錄

```text
charts/    放 Helm Chart（含範例 charts/sample-app）
rendered/  helm template 輸出（生成物）
diagrams/  SVG/PNG（生成物）
notes/     你的 LLM 分析筆記
```

## 下一步（bootstrap §10–11）

把 `Chart.yaml`、`values.yaml`、`rendered/<name>-rendered.yaml`、`diagrams/<name>.png`
一起交給本地 LLM，用 bootstrap §11 的「Kubernetes Architecture Learning Agent」
prompt 分析，結果寫進 `notes/`。

## Credits / 參考工具

本 repo 不含任何第三方程式碼；以下工具是外部依賴（CLI 或 `.venv/` 內的 pip 套件，
皆已被 gitignore），僅在此註明來源與授權：

- [KubeDiagrams](https://github.com/falkeio/kubediagrams) — topology 圖產生器（本工具的核心）, Apache-2.0
  - 線上版：<https://kubediagrams.lille.inria.fr/>
- [diagrams](https://github.com/mingrammer/diagrams) — KubeDiagrams 底層繪圖庫, Apache-2.0
- [Helm](https://github.com/helm/helm) — chart render / lint, Apache-2.0
- [pygraphviz](https://github.com/pygraphviz/pygraphviz) — graph 資料結構, MIT-like (BSD 3-clause)
- [Graphviz](https://graphviz.org/) — 圖渲染引擎（系統 binary）, GPLv3（linking exception）

## License

本 repo 原創內容（`bin/`、`charts/`、`notes/`、文件）以 [MIT](LICENSE) 授權。

> **注意**：`diagrams/` 內的生成圖檔**不要 commit**。KubeDiagrams 的圖示
> 部分來自品牌資產（如 AWS/Azure/RedHat 官方 icon），公開前請自行判斷；
> 本 repo 的 `.gitignore` 已預設排除 `diagrams/`、`rendered/`、`.venv/`。

## 環境重設（如果換機器）

```bash
brew install helm graphviz pkgconf
CFLAGS="-I/opt/homebrew/opt/graphviz/include" \
LDFLAGS="-L/opt/homebrew/opt/graphviz/lib" \
  python3 -m venv .venv
.venv/bin/pip install pygraphviz==1.14 kubediagrams
```

> 注意：`kubediagrams 0.8.0` 鎖 `pygraphviz==1.14`（只有 source 版），
> 必須先裝 graphviz 並給明確 CFLAGS/LDFLAGS 才能 build。
> Homebrew 的 graphviz 16 沒有 umbrella `graphviz.pc`，所以不能靠 pkg-config 自動偵測。
