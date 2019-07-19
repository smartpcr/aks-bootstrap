---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: secret-broker
  labels:
    app: secret-broker
spec:
  replicas: 2
  selector:
    matchLabels:
      app: secret-broker
  template:
    metadata:
      labels:
        app: secret-broker
    spec:
      # Needs to run in production as root, because azure.json is root-only
      securityContext:
        runAsUser: 0
      containers:
        - name: secret-broker
          image: "{{.Values.acr.name}}.azurecr.io/1es/secret-broker:{{.Values.service.image.tag}}"
          resources:
            requests:
              cpu: "50m"
              memory: "75Mi"
            limits:
              cpu: "100m"
              memory: "250Mi"
          env:
            - name: TENANT
              value: "{{.Values.geneva.tenant}}"
            - name: ROLE
              value: "{{.Values.aks.clusterName}}"
          livenessProbe:
            httpGet:
              port: 20000
              path: /status
              scheme: HTTPS
            initialDelaySeconds: 5
          volumeMounts:
            - name: ad-creds
              mountPath: /secrets/ad-creds
              readOnly: true
            - name: cert
              mountPath: /secrets/cert
              readOnly: true
      imagePullSecrets:
      - name: acr-auth
      volumes:
        - name: ad-creds
          hostPath:
            path: /etc/kubernetes
        - name: cert
          secret:
            secretName: ssl-aks-default-certificate

---
apiVersion: v1
kind: Service
metadata:
  name: secret-broker
spec:
  type: ClusterIP
  ports:
    - name: service-broker-https
      protocol: TCP
      port: 443
      targetPort: 20000
  selector:
    app: secret-broker
