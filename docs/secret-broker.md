We are using older version with unix socket, newer version changed to http

make sure secret broker using aad app that have access to key vault, this can be found in 
- pod: /secrets/ad-creds/azure.json 
- local: secretbroker in appsettings.json

after setup: exec into a pod and check its status
curl https://secret-broker.default.svc.cluster.local/status
curl 'https://secret-broker.default.svc.cluster.local/certificate?keyVault=int-disco-east-us&certificate=ssl-certificate-managed'


to run localbox using docker:
p ./dockercompose/restart.ps1 infrastructure/docker secret-broker
https://localhost:20000/certificate?keyVault=xiaodong-kv&certificate=onees-space-dev-xiaodong-wus2-spn