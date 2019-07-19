apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentityBinding 
metadata:
  name: "{{.Values.service.name}}-id-binding"
spec:
  AzureIdentity: "{{.Values.service.name}}"
  Selector: "{{.Values.service.label}}"