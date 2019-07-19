## Steps

### Custom steps for cluster (onees):

- Configure-AKS: add dns secret
- Configure-Onees-Cluster: when using app insights, also deploy cluster role for AI to read k8s resources 
- Deploy-Onees-Adf

### Custom steps for application:

- product-catalog-api
    - Create-ProductCatalog-CosmosDbResources
    - Create-PolicyCatalog-CosmosDbResources

### setup network security groups

    [code](https://msmobilecenter.visualstudio.com/Mobile-Center/_git/appcenter?path=%2Fdeployment%2Fdeployment%2FScripts%2FDeployment%2FNew-InfraDeploymentUnit.ps1&version=GBmaster&line=92&lineStyle=plain&lineEnd=93&lineStartColumn=1&lineEndColumn=1)

    ``` powershell
    CustomSteps\Link-Network-Security-Groups.ps1
    ```

### upload script files to infra storage account for a given entity

    - CustomScripts\Windows-BootstrapServiceFabricCluster.ps1
    - CustomScripts\Windows-ImportKeyVaultCertificate.ps1
    - CustomScripts\Windows-ConfigureCryptoCiphers.ps1
    - CustomScripts\Windows-UpdateDocker.ps1
    - CustomScripts\Windows-UpdateAspNetCore.ps1
    - CustomScripts\Windows-FixSSLAdminAuthorityDecember2017.bat
    - CustomScripts\Windows-EnableSSEScanning.ps1
    - CustomScripts\Windows-PrepareVMDisks.ps1
    - CustomScripts\Linux-InstallAzSecPack.sh
    - CustomScripts\Linux-10-appcenter.conf
    - CustomScripts\Linux-Logrotate.conf
    - CustomScripts\Linux-DefaultLogrotateTask.sh
    - CustomScripts\Linux-PrepareVMDisks.sh
    - CustomScripts\Linux-SetupMaintenance.sh

### Setup certificates

-   List of certificates:
    | cert | purpose |
    | --- | --- |
    | KeyVault-Certificate | |
    | AvalancheAdmin-Certificate | |
    | Ssl-Certificate | |
    | Ssl-Aks-Default-Certificate | |
    | Crash-Certificate | |
    | Ingestion-Certificate | |
    | Geneva-Certificate | |
    | Billing-Certificate | |
    | BillingPA-Certificate | |
    | TestRunner-Certificate | |
    | KustoIngestion-Certificate | |
    | PcfAgent-MSA-Certificate | |
    | Accounts-Management-Ssl-Certificate | |
    | Api-Gateway-Ssl-Certificate | |
    | AppCenterSsl-Certificate | |
    | Customer-Credential-Store-Ssl-Certificate | |
    | HockeyAppSxSSsl-Certificate | |
    | IngestionSsl-Certificate | |
    | Mail-Sender-Ssl-Certificate | |
    | Alerting-Certificate | |
    | Analytics-Certificate | |
    | Billing-Certificate | |
    | Coordinator-Certificate | |
    | CoordinatorExternalParticipants-Certificate | |
    | CrashIdentity-Certificate | |
    | Export-Certificate | |
    | HockeyAppGdprParticipant-Certificate | |
    | LogAnalyticsIngestion-Certificate | |
    | LogAnalyticsODS-Certificate | |
    | LogAnalyticsReader-Certificate | |
    | LogAnalyticsWorkspaceManager-Certificate | |
    | MBaaS-Certificate | |
    | MalwareScan-Certificate | |
    | OneesExtensionManager-Certificate | |
    | PcfAgent-Certificate | |
    | Policy-Certificate | |
    | ProductCatalog-Certificate | |
    | Push-Certificate | |
    | SubscriptionLinking-Certificate | |
    | TestCloud-Certificate | |
    | TestCloudParticipant-Certificate | |
    | TestRunner-Certificate | |
    | Watson-Certificate | |

-   steps

    [code](https://msmobilecenter.visualstudio.com/Mobile-Center/_git/appcenter?path=%2Fdeployment%2Fdeployment%2FScripts%2FDeployment%2FNew-InfraDeploymentUnit.ps1&version=GBmaster&line=102&lineStyle=plain&lineEnd=103&lineStartColumn=1&lineEndColumn=1)

    1. import certificate from key vault (as secret) and install on local cert store
    2. create key vault certificate (upload if thumbprint is different)
    3. copy secrets from local kv to meta kv
    4. create cluster rdp password and store in kv
    5. create storage encryption key

## Setup secrets & certificates

1. copy the following secret from source kv to your own kv
2. deploy the following certs to aks cluster

    - AppCenter-AKS-AADAppPwd
    - Geneva-Certificate
    - Ssl-Aks-Default-Certificate
    -

### Config AKS cluster (after ARM deployment)

``` PowerShell
Configure-AKS.ps1
```

1. get kube config (to be used to deploy resources to cluster)
2. get admin groups and set assign clusterAdmin role to their AAD objectId
    - group-app-center-all
    - group-app-center-fte-all
    - group-app-center-vendors
    - group-1es-fte-all
3. grant dashboard cluster-admin role
4. upload primary domain SSL cert (from meta vault `devavalanches`)
    ```PowerShell
    Set-KubernetesSslCertificate -VaultName $metaVaultName -CertificateName Ssl-Certificate -KubeConfigFile $kubeConfigFile
    ```
5. upload ssl cert (`ssl-aks-default-certificate`) for `default` namespace
6. upload alt certs

    - Accounts-Management-Ssl-Certificate
    - Api-Gateway-Ssl-Certificate
    - AppCenterSsl-Certificate
    - Customer-Credential-Store-Ssl-Certificate
    - HockeyAppSxSSsl-Certificate
    - IngestionSsl-Certificate
    - Mail-Sender-Ssl-Certificate
    - Oauth-Token-Storage-Ssl-Certificate
    - PortalServerInstallSsl-Certificate
    - CiApiIntTrafficManagerSsl-Certificate
    - CiApiLiveIntTrafficManagerSsl-Certificate
    - CiAccountsIntTrafficManagerSsl-Certificate
    - MobileCenterAvalanchesSsl-Certificate
    - NotificationHub-Ssl-Certificate
7. upload geneva cert (`Geneva-Certificate`)
    ``` PowerShell
    Set-KubernetesCertificate `
    -VaultName $metaVaultName `
    -CertificateName Geneva-Certificate `
    -SecretCertName 'gcscert.pem' `
    -SecretKeyName 'gcskey.pem' `
    -KubeConfigFile $kubeConfigFile
    ```
8. get AKS service profile secret (`AKS-Service-Profile`)
    |clientId | secret |
    | -- | -- |
    |2e4c24df-5f5c-459d-9c01-beaf48af53e8 | SsaTQ8x8GMrqZX4ircKV2qmLRjjAdEg+VYmtivy09UE= |
9. upload credentials for external dns as aks secret (`external-dns-config-file`) in namespace `default` with data `azure.json`
    ``` JSON
    {
        "subscriptionId":  "5a7c335f-ef8e-4c07-9bca-866d3460876a",
        "tenantId":  "72f988bf-86f1-41af-91ab-2d7cd011db47",
        "aadClientId":  "2e4c24df-5f5c-459d-9c01-beaf48af53e8",
        "aadClientSecret":  "SsaTQ8x8GMrqZX4ircKV2qmLRjjAdEg+VYmtivy09UE=",
        "resourceGroup":  "dev.avalanch.es"
    }
    ```
10. create storage account (`storageb1e8b039`) in node resource group, then create storage class in aks
    ``` yaml
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    metadata:
    name: system:azure-cloud-provider
    rules:
    - apiGroups: ['']
    resources: ['secrets']
    verbs:     ['get','create']

    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata:
    name: system:azure-cloud-provider
    roleRef:
    kind: ClusterRole
    apiGroup: rbac.authorization.k8s.io
    name: system:azure-cloud-provider
    subjects:
    - kind: ServiceAccount
    name: persistent-volume-binder
    namespace: kube-system

    ---
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
    name: azurefile
    provisioner: kubernetes.io/azure-file
    parameters:
    skuName: Standard_LRS

    ---
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
    name: azurefile-premium
    provisioner: kubernetes.io/azure-file
    parameters:
    skuName: Premium_LRS
  ```
11. set network security group rules
12. set network security group for subnet