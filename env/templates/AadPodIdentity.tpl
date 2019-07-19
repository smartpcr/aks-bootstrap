apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity 
metadata:
  name: {{.Values.service.name}}
spec:
  type: 0
  ResourceID: {{.Values.serviceIdentity.id}}
  ClientId: {{.Values.serviceIdentity.clientId}}