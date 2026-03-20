{{/*
Common labels for all Squad resources.
*/}}
{{- define "squad-agents.labels" -}}
app.kubernetes.io/name: squad-agents
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
squad.github.com/repository: {{ .Values.global.repository | replace "/" "_" }}
{{- end }}

{{/*
Selector labels (subset of common labels).
*/}}
{{- define "squad-agents.selectorLabels" -}}
app.kubernetes.io/name: squad-agents
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Full image path: acrLoginServer/imageName:tag
*/}}
{{- define "squad-agents.image" -}}
{{- if .Values.global.acrLoginServer -}}
{{ .Values.global.acrLoginServer }}/{{ .image.repository }}:{{ .image.tag | default "latest" }}
{{- else -}}
{{ .image.repository }}:{{ .image.tag | default "latest" }}
{{- end -}}
{{- end }}
