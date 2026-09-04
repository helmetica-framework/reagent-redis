{{/*
  These template names are prefixed with the chart's own name. The prefix is a
  placeholder that the transmuter rewrites while scaffolding a reagent, in every file
  under templates/ and in values.yaml, so it always matches the reagent's chart name.
*/}}

{{/*
Name of the chart.
*/}}
{{- define "redis.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
A fully qualified name for resources this chart adds on top of the service. Truncated at
63 chars, the limit on most kubernetes name fields (DNS naming spec). The chart name is
only appended when the release name does not already carry it.
*/}}
{{- define "redis.fullname" -}}
{{- $name := .Chart.Name }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Chart name and version, as used by the chart label.
*/}}
{{- define "redis.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels. Every resource this chart renders carries these.
*/}}
{{- define "redis.labels" -}}
helm.sh/chart: {{ include "redis.chart" . }}
{{ include "redis.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels. The subset that is stable across upgrades, for anything selecting pods
of this release.
*/}}
{{- define "redis.selectorLabels" -}}
app.kubernetes.io/name: {{ include "redis.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
A daily cron expression somewhere between 22:00 and 06:00, for a backup that has not been
given a schedule of its own. Takes a seed string and hashes it, so the time is the same on
every render of an instance, and two instances rarely share a minute. Rendering a fresh
random time instead would move the schedule on every reconcile.
*/}}
{{- define "redis.nightlySchedule" -}}
{{- $seed := adler32sum . | int64 }}
{{- $minute := mod $seed 60 }}
{{- $hour := mod (add 22 (mod (div $seed 60) 8)) 24 }}
{{- printf "%d %d * * *" $minute $hour }}
{{- end }}
