{{- define "linse.name" -}}linse{{- end }}

{{- define "linse.labels" -}}
app.kubernetes.io/name: linse
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "linse.selectorLabels" -}}
app.kubernetes.io/name: linse
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
