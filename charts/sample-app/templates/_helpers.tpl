{{/*
Common labels — 所有 object 都會帶這組 labels，方便 KubeDiagrams 分組。
*/}}
{{- define "sample-app.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}

{{/*
Selector labels — 只有「穩定」的 labels 才能放這邊。
Service.spec.selector 和 Deployment.spec.selector 都用它。
*/}}
{{- define "sample-app.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "sample-app.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
