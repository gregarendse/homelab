{{- if .Values.vpa.enabled }}
---
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: {{ include "server.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "server.labels" . | nindent 4 }}

spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "server.fullname" . }}
  updatePolicy:
    updateMode: {{ .Values.vpa.updateMode | quote }}
  resourcePolicy:
    containerPolicies:
    - containerName: {{ .Release.Name }}
      maxAllowed:
        cpu: {{ .Values.vpa.maxAllowed.cpu }}
        memory: {{ .Values.vpa.maxAllowed.memory }}
      minAllowed:
        cpu: {{ .Values.vpa.minAllowed.cpu }}
        memory: {{ .Values.vpa.minAllowed.memory }}
{{- end }}
