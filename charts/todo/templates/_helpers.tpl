{{- define "todo.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "todo.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "todo.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "todo.namespace" -}}
{{- default "todo-app" .Values.namespace | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "todo.componentName" -}}
{{- $root := index . 0 -}}
{{- $component := index . 1 -}}
{{- printf "%s-%s" (include "todo.fullname" $root) $component | trunc 63 | trimSuffix "-" -}}
{{- end -}}
