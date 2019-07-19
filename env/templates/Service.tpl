apiVersion: v1 
kind: Service 
metadata:
  name: "{{.Values.service.name}}" 
spec:
  type: LoadBalancer
  ports:
  - port: 80
  selector:
    app: "{{.Values.service.name}}"