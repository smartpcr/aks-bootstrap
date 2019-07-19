---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: geneva
  namespace: "{{.Values.geneva.k8sNamespace}}"

---
apiVersion: v1
kind: Service
metadata:
  name: geneva-services
  labels:
    app: geneva-services
spec:
  type: ClusterIP
  ports:
    - name: mdsd-fluentd-tcp
      protocol: TCP
      port: 24224
      targetPort: 24224
  selector:
    name: geneva-services

---
apiVersion: v1
kind: Service
metadata:
  name: geneva-metrics
  labels:
    app: geneva-services
spec:
  type: ClusterIP
  ports:
    - name: mdm-statsd-udp
      protocol: UDP
      port: 8125
      targetPort: 8125
  selector:
    name: geneva-services-statsd

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mdsd-conf
data:
  mdsd.xml: $(RenderTemplate -File mdsd.xml -Encoding YAML)

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-conf
data:
  fluentd-api.conf: $(RenderTemplate -File fluentd-api.conf -Encoding YAML)
  fluentd-container-logs.conf: $(RenderFile -File fluentd-container-logs.conf -Encoding YAML)
  fluentd-systemd.conf: $(RenderFile -File fluentd-systemd.conf -Encoding YAML)
  fluentd.conf: $(RenderTemplate -File fluentd.conf -Encoding YAML)

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: janitor-conf
data:
  logrotate_mdsd.conf: $(RenderFile -File logrotate_mdsd.conf -Encoding YAML)
  janitor_start.sh: $(RenderFile -File janitor_start.sh -Encoding YAML)

---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: geneva
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: geneva
    namespace: "{{.Values.geneva.k8sNamespace}}"

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: geneva-services-statsd
  labels:
    app: geneva-services
spec:
  selector:
    matchLabels:
      name: geneva-services-statsd
  replicas: {{.Values.geneva.replicas}}
  template:
    metadata:
      labels:
        name: geneva-services-statsd
    spec:
      serviceAccount: geneva
      containers:
        # MDM
        - name: mdm
          image: "{{.Values.acr.name}}.azurecr.io/{{.Values.geneva.mdm.image.name}}:{{.Values.geneva.mdm.image.tag}}"
          env:
            - name: METRIC_ENDPOINT
              value: "https://global.metrics.nsatc.net/"
            - name: MDM_ACCOUNT
              value: "{{.Values.geneva.account}}"
            - name: MDM_LOG_LEVEL
              value: "Error"
            - name: MDM_INPUT
              value: statsd_udp
            - name: CERT_FILE
              value: "/secrets/gcscert.pem"
            - name: KEY_FILE
              value: "/secrets/gcskey.pem"
          volumeMounts:
            - name: mdm-auth-vol
              mountPath: /secrets

      imagePullSecrets:
      - name: acr-auth

      volumes:
        # MDM
        - name: mdm-auth-vol
          secret:
            secretName: geneva-certificate

---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: geneva-services
  labels:
    app: geneva-services
spec:
  updateStrategy:
    type: RollingUpdate
  selector:
    matchLabels:
      name: geneva-services
  template:
    metadata:
      annotations:
        mdsd.xml-crc32: "$(RenderTemplate -File mdsd.xml -Encoding CRC32)"
        fluentd-api.conf-crc32: "$(RenderTemplate -File fluentd-api.conf -Encoding CRC32)"
        fluentd-container-logs.conf-crc32: "$(RenderFile -File fluentd-container-logs.conf -Encoding CRC32)"
        fluentd-systemd.conf-crc32: "$(RenderFile -File fluentd-systemd.conf -Encoding CRC32)"
        fluentd.conf-crc32: "$(RenderTemplate -File fluentd.conf -Encoding CRC32)"
      labels:
        name: geneva-services
    spec:
      hostNetwork: true
      serviceAccount: geneva
      containers:

        # MDSD
        - name: mdsd
          image: "{{.Values.acr.name}}.azurecr.io/{{.Values.geneva.mdsd.image.name}}:{{.Values.geneva.mdsd.image.tag}}"
          resources:
            requests:
              cpu: "250m"
              memory: "2Gi"
            limits:
              cpu: "500m"
              memory: "4Gi"
          env:
          - name: TENANT
            value: "{{.Values.geneva.tenant}}"
          - name: ROLE
            value: "{{.Values.geneva.role}}"
          - name: ROLEINSTANCE
            valueFrom:
              fieldRef:
                fieldPath: spec.nodeName
          - name: MONITORING_GCS_ENVIRONMENT
            value: "{{.Values.geneva.environment}}"
          - name: MONITORING_GCS_ACCOUNT
            value: "{{.Values.geneva.account}}"
          - name: MONITORING_GCS_REGION
            value: "{{.Values.aks.location}}"
          volumeMounts:
            - name: mdsd-auth-vol
              mountPath: /geneva/geneva_auth
            - name: mdsd-conf-vol
              mountPath: /geneva/geneva_config
            - name: var-log-vol
              mountPath: /geneva/geneva_logs
            - name: mdsd-run-vol
              mountPath: /var/run/mdsd

        # FluentD
        - name: fluentd
          image: "{{.Values.acr.name}}.azurecr.io/{{.Values.geneva.fluentd.image.name}}:{{.Values.geneva.fluentd.image.tag}}"
          env:
            - name: FLUENTD_CONF
              value: /etc/fluentd/fluentd.conf
          volumeMounts:
            - name: fluentd-conf-vol
              mountPath: /etc/fluentd
            - name: fluentd-buffer-vol
              mountPath: "/var/log/td-agent"
            - name: mdsd-run-vol
              mountPath: "/var/run/mdsd"
            - name: docker-log-vol
              mountPath: /var/lib/docker/containers
              readOnly: true
            - name: var-log-vol
              mountPath: /var/log
            - name: run-journal-vol
              mountPath: /run/log/journal
              readOnly: true

        # Janitor
        - name: janitor
          image: alpine
          command: ["/bin/sh"]
          args: ["/janitor/janitor_start.sh"]
          volumeMounts:
            - name: var-log-vol
              mountPath: /geneva/geneva_logs
            - name: janitor-conf-vol
              mountPath: /janitor

        # AzSecPack
        - name: azsecpack
          image: "{{.Values.acr.name}}.azurecr.io/{{.Values.geneva.azsecpack.image.name}}:{{.Values.geneva.azsecpack.image.tag}}"
          resources:
            requests:
              cpu: "50m"
              memory: "75Mi"
            limits:
              cpu: "100m"
              memory: "250Mi"
          env:
            - name: AzSecPack_GCS_cert
              value: "/secrets/gcscert.pem"
            - name: AzSecPack_GCS_key
              value: "/secrets/gcskey.pem"
            - name: AzSecPack_GCS_Environment
              value: "{{.Values.global.envName}}"
            - name: AzSecPack_GCS_Account
              value: "{{.Values.geneva.account}}"
            - name: AzSecPack_EventVersion
              value: "8"
            - name: AzSecPack_Timestamp
              value: "2018-05-08T20:00:00.000"
            - name: AzSecPack_Namespace
              value: "{{.Values.geneva.namespace}}"
            - name: AzSecPack_Moniker
              value: "{{.Values.geneva.mdsd.monikers.security.name}}"
            - name: AzSecPack_Tenant
              value: "{{.Values.geneva.tenant}}"
            - name: AzSecPack_Role
              value: "{{.Values.geneva.role}}"
            - name: AzSecPack_RoleInstance
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: AzSecPack_MachineName
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: AzSecPack_MonitorForFailure
              value: "1"
          volumeMounts:
            - mountPath: /host
              name: azsecpack-host
              readOnly: false
            - mountPath: /secrets
              name: azsecpack-auth-vol

      imagePullSecrets:
      - name: acr-auth

      volumes:

        # MDSD
        - name: mdsd-conf-vol
          configMap:
            name: mdsd-conf
        - name: mdsd-run-vol
          emptyDir: {}
        - name: mdsd-auth-vol
          secret:
            secretName: geneva-certificate

        # FluentD
        - name: fluentd-conf-vol
          configMap:
            name: fluentd-conf
        - name: fluentd-buffer-vol
          emptyDir: {}
        - name: docker-log-vol
          hostPath:
            path: /var/lib/docker/containers
        - name: run-journal-vol
          hostPath:
            path: /run/log/journal
        - name: var-log-vol
          hostPath:
            path: /var/log

        # AzSecPack
        - name: azsecpack-host
          hostPath:
            path: /
        - name: azsecpack-auth-vol
          secret:
            secretName: geneva-certificate

        # Janitor
        - name: janitor-conf-vol
          configMap:
            name: janitor-conf
