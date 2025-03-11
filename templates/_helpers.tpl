{{/*Return a tbmq node label*/}}
{{- define "tbmq.node.label" -}}
{{ printf "%s-tbmq-node" .Release.Name }}
{{- end }}

{{/*Return a tbmq node image*/}}
{{- define "tbmq.node.image" -}}
{{- $repository := .Values.tbmq.image.repository | default "thingsboard/tbmq-node" }}
{{- $appversion := .Values.tbmq.image.tag | default (printf "%s" .Chart.AppVersion) }}
{{- printf "%s:%s" $repository $appversion }}
{{- end }}

{{/*Return a tbmq ie label*/}}
{{- define "tbmq.ie.label" -}}
{{ printf "%s-tbmq-ie" .Release.Name }}
{{- end }}

{{/*Return a tbmq ie host*/}}
{{- define "tbmq.ie.host" -}}
{{ printf "%s-tbmq-ie" .Release.Name }}
{{- end }}

{{/*Return a tbmq ie image*/}}
{{- define "tbmq.ie.image" -}}
{{- $repository := index .Values "tbmq-ie" "image" "repository" | default "thingsboard/tbmq-integration-executor" }}
{{- $appversion := index .Values "tbmq-ie" "image" "tag" | default (printf "%s" .Chart.AppVersion) }}
{{- printf "%s:%s" $repository $appversion }}
{{- end }}

{{/*Return redis cluster configurations environment variables for tbmq services*/}}
{{- define "tbmq.redis.configuration.ref"}}
- configMapRef:
    name: {{ .Release.Name }}-redis-config
- secretRef:
    name: {{ .Release.Name }}-redis-secret
{{- end}}

{{/*Return redis cluster nodes*/}}
{{- define "tbmq.redis.nodes" -}}
{{- if index .Values "redis-cluster" "fullnameOverride" }}
  {{- printf "%s-headless:6379" (index .Values "redis-cluster" "fullnameOverride") -}}
{{- else }}
  {{- printf "%s-%s-headless:6379" .Release.Name (index .Values "redis-cluster" "nameOverride") -}}
{{- end }}
{{- end }}

{{/*Return postgresql configurations environment variables for tbmq services*/}}
{{- define "tbmq.postgres.configuration.ref"}}
- configMapRef:
    name: {{ .Release.Name }}-postgres-config
- secretRef:
    name: {{ .Release.Name }}-postgres-secret
{{- end}}

{{/*Return postgres host*/}}
{{- define "tbmq.postgres.host" -}}
{{- if .Values.postgresql.enabled -}}
  {{- if .Values.postgresql.fullnameOverride }}
    {{- .Values.postgresql.fullnameOverride -}}
  {{- else }}
    {{- printf "%s-%s" .Release.Name .Values.postgresql.nameOverride -}}
  {{- end }}
{{- else }}
  {{- .Values.externalPostgresql.host -}}
{{- end }}
{{- end }}

{{- define "tbmq.postgres.port" -}}
{{- if .Values.postgresql.enabled -}}
5432
{{- else -}}
{{- .Values.externalPostgresql.port -}}
{{- end -}}
{{- end }}

{{/*Return postgres database name*/}}
{{- define "tbmq.postgres.database" -}}
{{- if .Values.postgresql.enabled -}}
{{- .Values.postgresql.auth.database -}}
{{- else -}}
{{- .Values.externalPostgresql.database -}}
{{- end -}}
{{- end }}

{{/*Return postgres username*/}}
{{- define "tbmq.postgres.username" -}}
{{- if .Values.postgresql.enabled -}}
{{- .Values.postgresql.auth.username -}}
{{- else -}}
{{- .Values.externalPostgresql.username -}}
{{- end -}}
{{- end }}

{{/*Return kafka configurations environment variables for tbmq services*/}}
{{- define "tbmq.kafka.configuration.ref"}}
- configMapRef:
    name: {{ .Release.Name }}-kafka-config
{{- end}}

{{/*Return kafka servers environment variables for tbmq services*/}}
{{- define "tbmq.kafka.servers" -}}
{{- if index .Values "kafka" "fullnameOverride" }}
  {{- printf "%s:9092" (index .Values "kafka" "fullnameOverride") -}}
{{- else }}
  {{- printf "%s-%s:9092" .Release.Name (index .Values "kafka" "nameOverride") -}}
{{- end }}
{{- end }}

{{/*Return tbmq image pull secret*/}}
{{- define "tbmq.imagePullSecret" }}
{{- printf "{\"auths\": {\"%s\": {\"auth\": \"%s\"}}}" .Values.dockerAuth.registry (printf "%s:%s" .Values.dockerAuth.username .Values.dockerAuth.password | b64enc) | b64enc }}
{{- end }}

{{/*Init container that will slow deployment and let Service deploy after all scripts in the container exit successfully or timeout.*/}}
{{- define "tbmq.initcontainers" }}
{{- $context:= index . "context" | default . }}
{{- $query := index . "pg_query" | default "Select count(*) from tb_schema_settings;" }}
- name: validate-db
  image: thingsboard/toolbox:1.13.0
  env:
    - name: RETRY_COUNT
      value: "5"
    - name: SECONDS_BETWEEN_RETRY
      value: "30"
    - name: PGHOST
      value: {{ include "tbmq.postgres.host" . | quote }}
    - name: PGDATABASE
      value: {{ include "tbmq.postgres.database" . | quote }}
    - name: PGUSER
      value: {{ include "tbmq.postgres.username" . | quote }}
    - name: QUERY_TO_VALIDATE_DATA
      value: {{ $query | quote }}
    - name: PGPASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ $context.Release.Name }}-postgres-secret
          key: SPRING_DATASOURCE_PASSWORD
  command:
    - bash
  args:
    - script-runner.sh
    - psql-validator.sh
{{- end }}
