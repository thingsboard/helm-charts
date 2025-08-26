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

{{/*Return redis cluster configurations environment variables for tbmq services*/}}
{{- define "tbmq.redis.configuration.ref"}}
- configMapRef:
    name: {{ .Release.Name }}-redis-config
{{- end}}

{{/*Returns redis cluster secret name*/}}
{{- define "tbmq.redis.secretName" -}}
{{- $redis := index .Values "redis-cluster" -}}
{{- if $redis.enabled -}}
{{- if $redis.existingSecret -}}
{{- $redis.existingSecret -}}
{{- else if $redis.fullnameOverride -}}
{{- $redis.fullnameOverride -}}
{{- else if $redis.nameOverride -}}
{{- printf "%s-%s" .Release.Name $redis.nameOverride -}}
{{- else -}}
{{- printf "%s-redis-cluster" .Release.Name -}}
{{- end -}}
{{- else -}}
{{- $external := index .Values "external-redis-cluster" -}}
{{- if $external.existingSecret -}}
{{- $external.existingSecret -}}
{{- else -}}
{{- printf "%s-redis-cluster-external" .Release.Name -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*Returns redis cluster secret key*/}}
{{- define "tbmq.redis.secretKey" -}}
{{- $redis := index .Values "redis-cluster" -}}
{{- if $redis.enabled -}}
{{- if $redis.existingSecret -}}
{{ $redis.existingSecretPasswordKey | default "REDIS_PASSWORD" -}}
{{- else -}}
redis-password
{{- end -}}
{{- else -}}
{{- $external := index .Values "external-redis-cluster" -}}
{{- if $external.existingSecret -}}
{{- $external.existingSecretPasswordKey | default "REDIS_PASSWORD" -}}
{{- else -}}
redis-password
{{- end -}}
{{- end -}}
{{- end -}}

{{/*Returns if Redis should use password*/}}
{{- define "tbmq.redis.passwordEnabled" -}}
{{- $redis := index .Values "redis-cluster" -}}
{{- if $redis.enabled -}}
{{- $redis.usePassword -}}
{{- else -}}
{{- $external := index .Values "external-redis-cluster" -}}
{{ $external.usePassword -}}
{{ end -}}
{{ end -}}

{{/*Return redis cluster nodes*/}}
{{- define "tbmq.redis.nodes" -}}
{{- $redis := index .Values "redis-cluster" -}}
{{- if $redis.enabled }}
{{- if index .Values "redis-cluster" "fullnameOverride" }}
{{- printf "%s-headless:6379" (index .Values "redis-cluster" "fullnameOverride") -}}
{{- else if index .Values "redis-cluster" "nameOverride" }}
{{- printf "%s-%s-headless:6379" .Release.Name (index .Values "redis-cluster" "nameOverride") -}}
{{- else }}
{{- printf "%s-redis-cluster-headless:6379" .Release.Name -}}
{{- end }}
{{- else -}}
{{- $external := index .Values "external-redis-cluster" -}}
{{- $external.nodes -}}
{{- end }}
{{- end }}

{{/*Return postgresql configurations environment variables for tbmq services*/}}
{{- define "tbmq.postgres.configuration.ref"}}
- configMapRef:
    name: {{ .Release.Name }}-postgres-config
{{- end}}

{{/*Return postgresql secret name*/}}
{{- define "tbmq.postgres.secretName" -}}
{{- if not .Values.postgresql.enabled }}
{{- printf "%s-postgres-external" .Release.Name }}
{{- else if .Values.postgresql.auth.existingSecret }}
{{- .Values.postgresql.auth.existingSecret }}
{{- else if .Values.postgresql.fullnameOverride }}
{{- .Values.postgresql.fullnameOverride }}
{{- else if .Values.postgresql.nameOverride }}
{{- printf "%s-%s" .Release.Name .Values.postgresql.nameOverride }}
{{- else }}
{{- printf "%s-postgresql" .Release.Name }}
{{- end }}
{{- end }}

{{/*Return postgresql secret key*/}}
{{- define "tbmq.postgres.secretKey" -}}
{{- if not .Values.postgresql.enabled -}}
external-postgres-password
{{- else if .Values.postgresql.auth.existingSecret }}
    {{- if and .Values.postgresql.auth.enablePostgresUser (not .Values.postgresql.auth.username) -}}
        {{- .Values.postgresql.auth.secretKeys.adminPasswordKey }}
    {{- else }}
        {{- .Values.postgresql.auth.secretKeys.userPasswordKey }}
    {{- end -}}
{{- else -}}
    {{- if and .Values.postgresql.auth.enablePostgresUser (not .Values.postgresql.auth.username) -}}
        postgres-password
    {{- else -}}
        password
    {{- end -}}
{{- end -}}
{{- end }}

{{/*Return postgres host*/}}
{{- define "tbmq.postgres.host" -}}
{{- if .Values.postgresql.enabled -}}
  {{- if .Values.postgresql.fullnameOverride }}
    {{- .Values.postgresql.fullnameOverride -}}
  {{- else if .Values.postgresql.nameOverride }}
    {{- printf "%s-%s" .Release.Name .Values.postgresql.nameOverride -}}
  {{- else }}
    {{- printf "%s-postgresql" .Release.Name -}}
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
    {{- if .Values.postgresql.auth.username -}}
        {{- .Values.postgresql.auth.username -}}
    {{- else -}}
        postgres
    {{- end }}
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
{{- if .Values.kafka.enabled -}}
{{- if .Values.kafka.fullnameOverride }}
{{- printf "%s:9092" .Values.kafka.fullnameOverride -}}
{{- else if .Values.kafka.nameOverride -}}
{{- printf "%s-%s:9092" .Release.Name .Values.kafka.nameOverride -}}
{{- else }}
{{- printf "%s-kafka:9092" .Release.Name -}}
{{- end -}}
{{- else -}}
{{- .Values.externalKafka.bootstrapServers -}}
{{- end -}}
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
