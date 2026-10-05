{{/* 모든 리소스에 붙는 공통 라벨. selector 에는 쓰지 않는다 (app: be 등만 쓴다) */}}
{{- define "myproject.labels" -}}
app.kubernetes.io/part-of: myproject
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/* repository:tag. tag 가 비면 렌더링을 멈춘다. 사용: include "myproject.image" (list .Values.be.image "be") */}}
{{- define "myproject.image" -}}
{{- $img := index . 0 -}}
{{- $name := index . 1 -}}
{{ $img.repository }}:{{ required (printf "%s.image.tag 를 지정하세요 (예: --set %s.image.tag=v1.0.0)" $name $name) $img.tag }}
{{- end }}

{{/* Service 의 type · nodePort. 사용: include "myproject.servicePorts" .Values.be.service */}}
{{- define "myproject.servicePorts" -}}
type: {{ .type }}
ports:
  - port: {{ .port }}
    targetPort: {{ .port }}
    {{- if and (eq .type "NodePort") .nodePort }}
    nodePort: {{ .nodePort }}
    {{- end }}
{{- end }}
