apiVersion: extensions/v1beta1
kind: Deployment 
metadata:
  labels:
    app: "{{.Values.service.name}}"
    aadpodidbinding: "{{.Values.service.label}}"
  name: {{.Values.service.name}}
  namespace: {{.Values.service.namespace}}
spec:
  template:
    metadata:
      labels:
        app: {{.Values.service.name}}
        aadpodidbinding: {{.Values.service.label}}
    spec:
      containers:
      - name: {{.Values.service.name}}
        image: "{{.Values.service.image.name}}:{{.Values.service.image.tag}}"
        imagePullPolicy: Always 
        args:
          - "--subscriptionid={{.Values.subscriptionId}}"
          - "--clientid={{.Values.serviceIdentity.clientId}}"
          - "--resourcegroup={{.Values.serviceIdentity.resourceGroup}}"
          - "--aad-resourcename=https://vault.azure.net"
        env:
        - name: MY_POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name 
        - name: MY_POD_NAMESPACE 
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: MY_POD_IP 
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
      imagePullSecrets:
      - name: acr-auth
        
