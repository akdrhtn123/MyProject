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

{{/* be 서버와 마이그레이션 Job 이 같이 쓰는 환경변수 (같은 설정으로 같은 DB 에 붙어야 한다) */}}
{{- define "myproject.beEnv" -}}
envFrom:
  - configMapRef:
      name: be-config
env:
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef: { name: {{ .Values.secretName }}, key: POSTGRES_PASSWORD }
  # $(VAR) 는 같은 목록에서 먼저 정의한 env 로 치환된다
  - name: DATABASE_URL
    value: postgresql+asyncpg://agent:$(POSTGRES_PASSWORD)@postgres:5432/agent
  - name: JWT_SECRET
    valueFrom:
      secretKeyRef: { name: {{ .Values.secretName }}, key: JWT_SECRET }
  - name: ENCRYPTION_KEY
    valueFrom:
      secretKeyRef: { name: {{ .Values.secretName }}, key: ENCRYPTION_KEY }
  - name: ANTHROPIC_API_KEY
    valueFrom:
      secretKeyRef: { name: {{ .Values.secretName }}, key: ANTHROPIC_API_KEY, optional: true }
  - name: OPENAI_API_KEY
    valueFrom:
      secretKeyRef: { name: {{ .Values.secretName }}, key: OPENAI_API_KEY, optional: true }
{{- end }}
