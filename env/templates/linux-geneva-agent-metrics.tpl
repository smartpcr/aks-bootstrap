apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: geneva-metrics
  namespace: {{.Values.geneva.k8sNamespace}}
  labels:
    daemon: geneva-metrics
spec:
  selector:
    matchLabels:
      daemon: geneva-metrics
  template:
    metadata:
      labels:
        daemon: geneva-metrics
    spec:
      containers:
        - name: linux-geneva-agent-aksmsi
          image: "{{.Values.acr.name}}.azurecr.io/{{.Values.geneva.metricsAksmsi.image.name}}:{{.Values.geneva.metricsAksmsi.image.tag}}"
          volumeMounts:
            - name: ad-creds
              mountPath: /secrets/ad-creds
              readOnly: true
        - name: linux-geneva-agent-metrics
          image: "{{.Values.acr.name}}.azurecr.io/{{.Values.geneva.metrics.image.name}}:{{.Values.geneva.metrics.image.tag}}"
          resources:
            requests:
              cpu: "50m"
              memory: "250Mi"
            limits:
              cpu: "100m"
              memory: "500Mi"
          env:
            - name: METRIC_ENDPOINT
              value: "https://global.metrics.nsatc.net/"
            - name: MDM_ACCOUNT
              value: "{{.Values.geneva.account}}"
            - name: MDM_QUIET
              value: "true"
            - name: MDM_VERBOSE
              value: "false"
            - name: MDM_LOG_LEVEL
              value: "Error"
            - name: MDM_SSL_DIGEST
              value: "sha1"
            - name: KEY_VAULT
              value: "{{.Values.kv.name}}"
            - name: TENANT
              value: "{{.Values.azAccount.tenantId}}"
            - name: ROLE
              value: "{{.Values.aks.clusterName}}"
            - name: TELEGRAF_MEMORY
              value: "80m"
            - name: TELEGRAF_IMAGE
              value: "{{.Values.geneva.metricsTelegraf.image.name}}:{{.Values.geneva.metricsTelegraf.image.tag}}"
            - name: REGISTRY_URL
              value: "{{.Values.acr.name}}.azurecr.io"
            - name: REGISTRY_USERNAME
              value: "{{.Values.acr.name}}"
            - name: REGISTRY_PASSWORD
              value: "{{.Values.acr.pwd}}"
            - name: GENEVA_CERTIFICATE
              value: "{{.Values.geneva.cert.base64string}}"
            - name: GENEVA_CERTIFICATE_THUMBPRINT
              value: "{{.Values.geneva.cert.thumbprint}}"
            - name: HOST_ETC
              value: "/rootfs/etc"
            - name: HOST_PROC
              value: "/rootfs/proc"
            - name: HOST_SYS
              value: "/rootfs/sys"
            - name: HOST_MOUNT_PREFIX
              value: "/hostfs"
          volumeMounts:
            - name: docker
              mountPath: /var/run/docker.sock
            - name: etc
              mountPath: /rootfs/etc
              readOnly: true
            - name: etw
              mountPath: /var/etw
            - name: proc
              mountPath: /rootfs/proc
            - name: root
              mountPath: /hostfs
              readOnly: true
            - name: sys
              mountPath: /rootfs/sys
              readOnly: true
            - name: telegraf
              mountPath: /var/run/appcenter-telegraf
            - name: udev
              mountPath: /run/udev
              readOnly: true
      imagePullSecrets:
      - name: acr-auth
      volumes:
        - name: ad-creds
          hostPath:
            path: /etc/kubernetes
        - name: docker
          hostPath:
            path: /var/run/docker.sock
            type: Socket
        - name: etc
          hostPath:
            path: /etc
        - name: etw
          hostPath:
            path: /var/etw
        - name: proc
          hostPath:
            path: /proc
        - name: root
          hostPath:
            path: /
        - name: sys
          hostPath:
            path: /sys
        - name: telegraf
          hostPath:
            path: /var/run/appcenter-telegraf
            type: DirectoryOrCreate
        - name: udev
          hostPath:
            path: /run/udev

