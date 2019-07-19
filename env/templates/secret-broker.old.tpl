apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  labels:
    daemon: secret-broker
  name: secret-broker
  namespace: default
spec:
  selector:
    matchLabels:
      daemon: secret-broker
  template:
    metadata:
      labels:
        daemon: secret-broker
    spec:
      containers:
        - image: "{{.Values.acr.name}}.azurecr.io/1es/secret-broker:{{.Values.service.image.tag}}"
          imagePullPolicy: IfNotPresent
          livenessProbe:
            failureThreshold: 3
            httpGet:
              path: /status
              port: 5000
              scheme: HTTP
            initialDelaySeconds: 5
            periodSeconds: 10
            successThreshold: 1
            timeoutSeconds: 1
          name: secret-broker
          resources:
            limits:
              cpu: 100m
              memory: 250Mi
            requests:
              cpu: 50m
              memory: 75Mi
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          volumeMounts:
            - mountPath: /secrets/ad-creds
              name: ad-creds
              readOnly: true
            - mountPath: /secrets/cert
              name: cert
              readOnly: true
            - mountPath: /var/run/appcenter-telegraf
              name: telegraf
            - mountPath: /var/run/secret-broker
              name: unix-socket
          env:
          - name: FLUENTD_HOST
            value: geneva-services
      
      imagePullSecrets:
        - name: acr-auth

      volumes:
      - name: ad-creds
        hostPath:
          path: /etc/kubernetes
          type: ""
      - name: cert
        secret:
          defaultMode: 420
          secretName: ssl-aks-default-certificate
      - name: telegraf
        hostPath:
          path: /var/run/appcenter-telegraf
          type: DirectoryOrCreate
      - name: unix-socket
        hostPath:
          path: /var/run/secret-broker
          type: DirectoryOrCreate
  updateStrategy:
    rollingUpdate:
      maxUnavailable: 1
    type: RollingUpdate
