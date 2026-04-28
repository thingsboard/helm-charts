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

{{/*Return tbmq config map name*/}}
{{- define "tbmq.configMapName" -}}
{{- if .Values.tbmq.existingConfigMap -}}
{{ .Values.tbmq.existingConfigMap }}
{{- else if .Values.tbmq.existingJavaOptsConfigMap -}}
{{ .Values.tbmq.existingJavaOptsConfigMap }}
{{- else -}}
{{ printf "%s-tbmq-node-default-config" .Release.Name }}
{{- end -}}
{{- end }}

{{/*Return tbmq logback config map name*/}}
{{- define "tbmq.logbackConfigMapName" -}}
{{- if .Values.tbmq.existingConfigMap -}}
{{ .Values.tbmq.existingConfigMap }}
{{- else if .Values.tbmq.existingLogbackConfigMap -}}
{{ .Values.tbmq.existingLogbackConfigMap }}
{{- else -}}
{{ printf "%s-tbmq-node-default-logback-config" .Release.Name }}
{{- end -}}
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

{{/*Return tbmq-ie config map name*/}}
{{- define "tbmq-ie.configMapName" -}}
{{- $tbmqIe := index .Values "tbmq-ie" }}
{{- if $tbmqIe.existingConfigMap -}}
{{ $tbmqIe.existingConfigMap }}
{{- else if $tbmqIe.existingJavaOptsConfigMap -}}
{{ $tbmqIe.existingJavaOptsConfigMap }}
{{- else -}}
{{ printf "%s-tbmq-ie-default-config" .Release.Name }}
{{- end -}}
{{- end }}

{{/*Return tbmq-ie logback config map name*/}}
{{- define "tbmq-ie.logbackConfigMapName" -}}
{{- $tbmqIe := index .Values "tbmq-ie" }}
{{- if $tbmqIe.existingConfigMap -}}
{{ $tbmqIe.existingConfigMap }}
{{- else if $tbmqIe.existingLogbackConfigMap -}}
{{ $tbmqIe.existingLogbackConfigMap }}
{{- else -}}
{{ printf "%s-tbmq-ie-default-logback-config" .Release.Name }}
{{- end -}}
{{- end }}

{{/*Return redis configurations environment variables for tbmq services*/}}
{{- define "tbmq.redis.configuration.ref"}}
- configMapRef:
    name: {{ .Release.Name }}-redis-config
{{- end}}

{{/*Returns redis secret name*/}}
{{- define "tbmq.redis.secretName" -}}
{{- if .Values.redis.existingSecret -}}
{{- .Values.redis.existingSecret -}}
{{- else -}}
{{- printf "%s-redis-secret" .Release.Name -}}
{{- end -}}
{{- end -}}

{{/*Returns redis secret key*/}}
{{- define "tbmq.redis.secretKey" -}}
{{- if .Values.redis.existingSecret -}}
{{- .Values.redis.existingSecretPasswordKey | default "redis-password" -}}
{{- else -}}
redis-password
{{- end -}}
{{- end -}}

{{/*Returns if Redis should use password*/}}
{{- define "tbmq.redis.passwordEnabled" -}}
{{- .Values.redis.usePassword -}}
{{- end -}}

{{/*Return redis connection type*/}}
{{- define "tbmq.redis.connectionType" -}}
{{- .Values.redis.connectionType | default "cluster" -}}
{{- end -}}

{{/*Return redis host (standalone mode)*/}}
{{- define "tbmq.redis.host" -}}
{{- .Values.redis.host -}}
{{- end -}}

{{/*Return redis port (standalone mode)*/}}
{{- define "tbmq.redis.port" -}}
{{- .Values.redis.port | default 6379 -}}
{{- end -}}

{{/*Return redis cluster nodes*/}}
{{- define "tbmq.redis.nodes" -}}
{{- .Values.redis.nodes -}}
{{- end }}

{{/*Return postgresql configurations environment variables for tbmq services*/}}
{{- define "tbmq.postgres.configuration.ref"}}
- configMapRef:
    name: {{ .Release.Name }}-postgres-config
{{- end}}

{{/*Return postgresql secret name*/}}
{{- define "tbmq.postgres.secretName" -}}
{{- if .Values.postgresql.existingSecret -}}
{{- .Values.postgresql.existingSecret -}}
{{- else -}}
{{- printf "%s-postgres-secret" .Release.Name -}}
{{- end -}}
{{- end -}}

{{/*Return postgresql secret key*/}}
{{- define "tbmq.postgres.secretKey" -}}
{{- if .Values.postgresql.existingSecret -}}
{{- .Values.postgresql.existingSecretPasswordKey | default "postgres-password" -}}
{{- else -}}
postgres-password
{{- end -}}
{{- end -}}

{{/*Return postgres host*/}}
{{- define "tbmq.postgres.host" -}}
{{- .Values.postgresql.host -}}
{{- end }}

{{/*Return postgres port*/}}
{{- define "tbmq.postgres.port" -}}
{{- .Values.postgresql.port | default 5432 -}}
{{- end }}

{{/*Return postgres database name*/}}
{{- define "tbmq.postgres.database" -}}
{{- .Values.postgresql.database -}}
{{- end }}

{{/*Return postgres username*/}}
{{- define "tbmq.postgres.username" -}}
{{- .Values.postgresql.username | default "postgres" -}}
{{- end }}

{{/*Return kafka configurations environment variables for tbmq services*/}}
{{- define "tbmq.kafka.configuration.ref"}}
- configMapRef:
    name: {{ .Release.Name }}-kafka-config
{{- end}}

{{/*Whether PE license env injection is enabled — true when either license.secret or license.existingSecret is set*/}}
{{- define "tbmq.license.enabled" -}}
{{- if or .Values.license.secret .Values.license.existingSecret -}}true{{- end -}}
{{- end -}}

{{/*Return the name of the Secret that holds the PE license value*/}}
{{- define "tbmq.license.secretName" -}}
{{- if .Values.license.existingSecret -}}
{{ .Values.license.existingSecret }}
{{- else -}}
{{ printf "%s-tbmq-license-secret" .Release.Name }}
{{- end -}}
{{- end -}}

{{/*Return the key inside the license Secret that holds the license value*/}}
{{- define "tbmq.license.secretKey" -}}
{{- if .Values.license.existingSecret -}}
{{ .Values.license.existingSecretLicenseKey | default "license-key" }}
{{- else -}}
license-key
{{- end -}}
{{- end -}}

{{/*Return the filesystem path used by the license client for its per-pod instance data file*/}}
{{- define "tbmq.license.instanceDataFile" -}}
{{ .Values.license.instanceDataFile | default "/data/tbmq-instance-license-$(TB_SERVICE_ID).data" }}
{{- end -}}

{{/*Render the TBMQ_LICENSE_SECRET + TBMQ_LICENSE_INSTANCE_DATA_FILE env entries when license is configured*/}}
{{- define "tbmq.license.env" -}}
{{- if eq (include "tbmq.license.enabled" .) "true" }}
- name: TBMQ_LICENSE_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "tbmq.license.secretName" . }}
      key: {{ include "tbmq.license.secretKey" . }}
- name: TBMQ_LICENSE_INSTANCE_DATA_FILE
  value: {{ include "tbmq.license.instanceDataFile" . | quote }}
{{- end }}
{{- end -}}

{{/*Return kafka bootstrap servers*/}}
{{- define "tbmq.kafka.servers" -}}
{{- .Values.kafka.bootstrapServers -}}
{{- end -}}

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
    - name: PGPORT
      value: {{ include "tbmq.postgres.port" . | quote }}
    - name: PGDATABASE
      value: {{ include "tbmq.postgres.database" . | quote }}
    - name: PGUSER
      value: {{ include "tbmq.postgres.username" . | quote }}
    - name: QUERY_TO_VALIDATE_DATA
      value: {{ $query | quote }}
    - name: PGPASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ include "tbmq.postgres.secretName" . }}
          key: {{ include "tbmq.postgres.secretKey" . }}
  command:
    - bash
  args:
    - script-runner.sh
    - psql-validator.sh
{{- end }}
