# Goals
based on questions+answers in json file (passed in as argument), the solution will generate
- deployment scripts
    - settings
        - env.yaml file
        - values.yaml file
    - deployment script (run as user or service principal)
        - setup infrastructure
        - deploy service to aks cluster
    - included resources
        - service principal and aad integration
        - acr (sync with existing acr)
        - key vault (sync with existing kv)
        - aks cluster with addons (devspaces, http routing, monitoring)
        - nginx + external_dns (allow auto binding to any frondend services)
        - dns
        - cert-manager (with letsencrypt to auto issue/renew wildcard cert)
        - cosmosd db
        - service bus
- service manifest file
    - sln
    - csproj
    - nuget pkgs
    - common libs
    - update DI and use extension method to hookup
        - kv client
        - cosmos db client
        - ssl cert (always the same within aks cluster)
        - auth

# Usage

## collect answers to questions and generate evidence

``` cmd
aksbootstrap evidence collect "<answers output folder>"
```

- generated evidence file
``` json
{
  "global": {
    "productName": "onecs",
    "subscriptionName": "Compliance_Tools_Eng",
    "subscriptionId": "c5a015e6-a59b-45bd-a621-82f447f46034",
    "tenantId": "72f988bf-86f1-41af-91ab-2d7cd011db47",
    "location": "westus2",
    "envName": "dev",
    "spaceName": "xiaodong",
    "resourceGroup": "onecs",
    "servicePrincipal": "onecs-dev-xiaodong",
    "components": {
      "kv": true,
      "aks": true,
      "acr": true,
      "ai": true,
      "cosmosDb": {
        "docDb": true,
        "graphDb": true
      },
      "dns": true,
      "redis": true
    }
  },
  "azure": {
    "kv": {
      "name": "xd-kv"
    },
    "terraform": {
      "servicePrincipal": "onece-terraform-sp",
      "stateStorageAccountName": "onece-terraform-state"
    },
    "acr": {
      "name": "onecsdevacr",
      "passwordSecretName": "onecsdevacr-pwd",
      "email": "xiaodoli@microsoft.com"
    },
    "aks": {
      "clusterName": "onecs-cluster",
      "version": "1.13.7",
      "nodeCount": 2,
      "adminUserName": "xiaodoli@microsoft.com",
      "access": {
        "readers": [
          {
            "name": "Compliance Tooling Team",
            "type": "group"
          }
        ],
        "contributors": [
          {
            "name": "1cs dri",
            "type": "group"
          }
        ],
        "owners": [
          {
            "name": "xiaodoli@microsoft.com",
            "type": "user"
          }
        ]
      },
      "keyVaultAccess": ["podIdentity", "secretBroker"],
      "metrics": ["appInsights", "prometheus"],
      "logging": ["appInsights", "prometheus"],
      "tracing": ["appInsights", "openTracing"],
      "ingress": ["nginx"],
      "certs": [
        {
          "name": "KeyVault-Certificate"
        },
        {
          "name": "Ssl-Certificate"
        },
        {
          "name": "Ssl-Aks-Default-Certificate"
        },
        {
          "name": "Geneva-Certificate",
          "type": "geneva"
        }
      ]
    },
    "appInsights": {
      "name": "onecs-ai"
    },
    "cosmosDbs": [
      {
        "account": "onecs-docs",
        "api": "SQL",
        "db": "docs",
        "collections": [
          {
            "name": "xd001",
            "partition": "teamProjectCollectionId",
            "throughput": 1000
          }
        ]
      },
      {
        "account": "onecs-graph",
        "api": "Gremlin",
        "db": "graph",
        "collections": [
          {
            "name": "xd001",
            "partition": "teamProjectCollectionId",
            "throughput": 1000
          }
        ]
      }
    ],
    "serviceBus": {
      "name": "onecs-sb-dev",
      "queues": ["assessment-changes", "work-item-changes"],
      "topics": ["status"]
    },
    "dns": {
      "name": "onecs-dev-dns",
      "domain": "xiaodong.world",
      "sslCert": "xiaodong-world-tls",
      "domainOwnerEmail": "xiaodoli@microsoft.com"
    }
  },
  "code": {
    "external": [
      {
        "name": "service-tree",
        "endpoint": "https://servicetree.msftcloudes.com",
        "resourceId": "bee782c6-8654-4298-a692-90976578870d"
      },
      {
        "name": "kusto-vsosi",
        "endpoint": "https://vsosi.kusto.windows.net"
      }
    ],
    "privateFeeds": [
      {
        "name": "mseng",
        "url": "https://mseng.pkgs.visualstudio.com/_packaging/AzureDevOps/nuget/v3/index.json",
        "passwordFromEnvironment": "mseng"
      }
    ],
    "volumeShares": [
      {
        "name": "kv-cert",
        "hostPath": "~/.secrets",
        "containerPath": "/secrets/disk/keyvault-certificate",
        "localOnly": true
      }
    ],
    "resources": {
      "api": {
        "requests":{
          "memory": "200Mi",
          "cpu": "100m"
        },
        "limits":{
          "memory": "800Mi",
          "cpu": "750m"
        }
      },
      "job": {
        "requests":{
          "memory": "200Mi",
          "cpu": "100m"
        },
        "limits":{
          "memory": "800Mi",
          "cpu": "750m"
        }
      },
      "web": {
        "requests":{
          "memory": "250Mi",
          "cpu": "100m"
        },
        "limits":{
          "memory": "1000Mi",
          "cpu": "1500m"
        }
      }
    },
    "services": [
      {
        "name": "onecs-graph",
        "type": "api",
        "isFrontend": true,
        "containerPort": 19901,
        "livenessCheck": "/health/live",
        "readinessCheck": "/health/ready",
        "volumes": ["kv-cert"],
        "env": [
          {
            "name": "ASPNETCORE_ENVIRONMENT",
            "value": "xiaodong"
          }
        ]
      },
      {
        "name": "onecs-assessment",
        "type": "api",
        "isFrontend": true,
        "containerPort": 19902,
        "livenessCheck": "/health/live",
        "readinessCheck": "/health/ready",
        "volumes": ["kv-cert"],
        "env": [
          {
            "name": "ASPNETCORE_ENVIRONMENT",
            "value": "xiaodong"
          }
        ]
      },
      {
        "name": "onecs-web",
        "type": "web",
        "isFrontend": true,
        "containerPort": 19903,
        "livenessCheck": "/health/live",
        "readinessCheck": "/health/ready",
        "volumes": ["kv-cert"],
        "env": [
          {
            "name": "ASPNETCORE_ENVIRONMENT",
            "value": "xiaodong"
          }
        ]
      },
      {
        "name": "onecs-session-processor",
        "type": "job",
        "schedule": "* * */1 * *"
      }
    ]
  }
}

```

## validate collected answers to questions and generate evidence

``` cmd
aksbootstrap evidence validate "<evidence folder>"
```

## generate infra setup scripts
``` cmd
aksbootstrap infra gen "<evidence file>" "<script output folder>"
```

- generated yaml file
``` yaml
global:
  subscriptionName: Compliance_Tools_Eng
  subscriptionId: c5a015e6-a59b-45bd-a621-82f447f46034
  resourceGroup: onecs
  location: westus2
  productName: onecs
  components:
    terraform: false
    aks: true
    acr: true
    appInsights: false
    dns: true
    traffic: false
    redis: true
    cosmosDb:
      docDb: true
      mongoDb: false
      mongoDb: true
  envName: dev
  spaceName: xiaodong
kv:
  name: xd-kv
  resourceGroup: onecs
acr:
  name: onecsdevacr
  passwordSecretName:
  email:
  resourceGroup: onecs
terraform:
  resourceGroup: onecs
  servicePrincipal: onece-terraform-sp
  stateStorageAccountName: onece-terraform-state
appInsights:
  name: onecs-ai
  resourceGroup: onecs
cosmosdb:
  - name: onecs-docs:
    account: onecs-docs
    api: SQL
    db: docs
    collections:
      - name: xd001
        partition: teamProjectCollectionId
        throughput: 1000
  - name: onecs-graph:
    account: onecs-graph
    api: Gremlin
    db: graph
    collections:
      - name: xd001
        partition: teamProjectCollectionId
        throughput: 1000
aks:
  clusterName: onecs-cluster
  dnsPrefix:
  version: 1.13.7
  vmSize:
  nodeCount: 2
  ownerUpn:
  access:
  useDevSpaces: false
  useTerraform: false
  useIstio: false
  useCertManager: false
  keyVaultAccess:
    - podIdentity
    - secretBroker
  metrics:
    - appInsights
    - prometheus
  logging:
    - appInsights
    - prometheus
  tracing:
    - appInsights
    - openTracing
  ingress:
    - nginx
  certs:
    - name: KeyVault-Certificate
    - name: Ssl-Certificate
    - name: Ssl-Aks-Default-Certificate
    - name: Geneva-Certificate
      type: geneva
servicebus:
  name: onecs-sb-dev
  resourceGroup: onecs
  queues:
    - assessment-changes
    - work-item-changes
    topics:
    - status
dns:
  name: onecs-dev-dns
  domain: xiaodong.world
  sslCert: xiaodong-world-tls
  domainOwnerEmail: xiaodoli@microsoft.com
  resourceGroup: onecs

```

## run infra setup
``` cmd
aksbootstrap infra run "<script folder>"
```

## generate solution
``` cmd
aksbootstrap app gen "<evidence file>" "<code output folder>"
```

- generated yaml file
``` yaml
global:
  subscriptionName: Compliance_Tools_Eng
  subscriptionId: c5a015e6-a59b-45bd-a621-82f447f46034
  resourceGroup: onecs
  location: westus2
  productName: onecs
  components:
    terraform: false
    aks: true
    acr: true
    appInsights: false
    dns: true
    traffic: false
    redis: true
    cosmosDb:
      docDb: true
      mongoDb: false
      mongoDb: true
  envName: dev
  spaceName: xiaodong
  servicePrincipal: onecs-dev-xiaodong
kv:
  name: xd-kv
  resourceGroup: onecs
acr:
  name: onecsdevacr
  passwordSecretName: onecsdevacr-pwd
  email: xiaodoli@microsoft.com
  resourceGroup: onecs
externalServices:
  - name: service-tree:
    endpoint: https://servicetree.msftcloudes.com
    resourceId: bee782c6-8654-4298-a692-90976578870d
  - name: kusto-vsosi:
    endpoint: https://vsosi.kusto.windows.net
nugetFeeds:
  - name: mseng:
    url: https://mseng.pkgs.visualstudio.com/_packaging/AzureDevOps/nuget/v3/index.json
    passwordFromEnvironment: mseng
shares:
  - name: kv-cert:
    hostPath: ~/.secrets
    containerPath: /secrets/disk/keyvault-certificate
    localOnly: true
resources:
  - name: api
    requests
      memory: 200Mi
      cpu: 100m
    limits
      memory: 800Mi
      cpu: 750m
  - name: job
    requests
      memory: 200Mi
      cpu: 100m
    limits
      memory: 800Mi
      cpu: 750m
  - name: web
    requests
      memory: 250Mi
      cpu: 100m
    limits
      memory: 1000Mi
      cpu: 1500m
services:
  - name: onecs-graph
    type: api
    image:
      name: onecs-graph
      tag: {{.Values.buildNumber}}
    solutionFile: c:/Users/xiaodoli/Desktop/solution/onecs.sln
    projectFile: c:/Users/xiaodoli/Desktop/solution/Onecs.Graph/Onecs.Graph.csproj
    assemblyName: Onecs.Graph
    containerPort: 19901
    sshPort: 51022
    sslCert: xiaodong-world-tls
    isFrontEnd: true
    livenessCheck: /health/live
    readinessCheck: /health/ready
    volumes:
      - name: kv-cert
      env:
      - name: ASPNETCORE_ENVIRONMENT
        value: xiaodong
  - name: onecs-assessment
    type: api
    image:
      name: onecs-assessment
      tag: {{.Values.buildNumber}}
    solutionFile: c:/Users/xiaodoli/Desktop/solution/onecs.sln
    projectFile: c:/Users/xiaodoli/Desktop/solution/Onecs.Assessment/Onecs.Assessment.csproj
    assemblyName: Onecs.Assessment
    containerPort: 19902
    sshPort: 51022
    sslCert: xiaodong-world-tls
    isFrontEnd: true
    livenessCheck: /health/live
    readinessCheck: /health/ready
    volumes:
      - name: kv-cert
      env:
      - name: ASPNETCORE_ENVIRONMENT
        value: xiaodong
  - name: onecs-web
    type: web
    image:
      name: onecs-web
      tag: {{.Values.buildNumber}}
    solutionFile: c:/Users/xiaodoli/Desktop/solution/onecs.sln
    projectFile: c:/Users/xiaodoli/Desktop/solution/Onecs.Web/Onecs.Web.csproj
    assemblyName: Onecs.Web
    containerPort: 19903
    sshPort: 51022
    sslCert: xiaodong-world-tls
    isFrontEnd: true
    livenessCheck: /health/live
    readinessCheck: /health/ready
    volumes:
      - name: kv-cert
      env:
      - name: ASPNETCORE_ENVIRONMENT
        value: xiaodong
  - name: onecs-session-processor
    type: job
    image:
      name: onecs-session-processor
      tag: {{.Values.buildNumber}}
    solutionFile: c:/Users/xiaodoli/Desktop/solution/onecs.sln
    projectFile: c:/Users/xiaodoli/Desktop/solution/Onecs.Session.Processor/Onecs.Session.Processor.csproj
    assemblyName: Onecs.Session.Processor
    schedule: * * */1 * *
    restartPolicy: Never
    concurrencyPolicy: Forbid

```

## deploy solution to aks
``` cmd
aksbootstrap app deploy "<service manifest file>" "<script folder>"
```

## run solution on local
``` cmd
aksbootstrap app run "<service manifest file>" "<script folder>"
```