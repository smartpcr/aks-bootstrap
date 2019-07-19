apiVersion: v1
data:
  {{ .Values.key }}: {{ .Values.value }}
kind: Secret
metadata:
  name: {{ .Values.name }}
type: Opaque