param ressourceName string
param location string
param tags object

param logAnalyticsWorkspaceId string
param entraAdminGroupObjectIds array
param kubernetesVersion string = '1.35.1'
param systemNodeCount int = 3
param systemVmSize string = 'Standard_B2ms'

resource aksCluster 'Microsoft.ContainerService/managedClusters@2026-01-01' = {
  name: ressourceName
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // basics
    kubernetesVersion: kubernetesVersion
    supportPlan: 'KubernetesOfficial'
    dnsPrefix: ressourceName
    // rbac
    enableRBAC: true
    disableLocalAccounts: true
    aadProfile: {
      managed: true
      adminGroupObjectIDs: entraAdminGroupObjectIds
      enableAzureRBAC: true
      tenantID: tenant().tenantId
    }
    // identity
    servicePrincipalProfile: {
      clientId: 'msi' // use managed kubelet identity
    }
    podIdentityProfile: {
      enabled: false // disable AAD Pod Identity as it is deprecated and will be retired in AKS in favor of workload identity
    }
    oidcIssuerProfile: {
      enabled: true // required for workload identity
    }
    // networking
    networkProfile: {
      // cloud CNI setup
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'azure'
      networkDataplane: 'azure'
      outboundType: 'loadBalancer'
      loadBalancerSku: 'standard'
      loadBalancerProfile: {
        managedOutboundIPs: {
          count: 1
        }
      }
      // cluster CIDR configuration - required for Azure CNI
      podCidr: '10.245.0.0/16'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: cidrHost('10.0.0.0/16', 9) // use .10 as dns service ip, this is default in AKS
    }
    // updates
    autoUpgradeProfile: {
      upgradeChannel: 'patch' // Azure default
      nodeOSUpgradeChannel: 'NodeImage' // Azure default
    }
    // aks addons
    addonProfiles: {
      // enable azure key vault secrets provider addon for integration with key vaults
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'false'
          rotationPollInterval: '2m'
        }
      }
      // enable azure policies via policy agent
      azurepolicy: {
        enabled: true
      }
      // oms agent for monitoring with log analytics workspace
      omsAgent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
          useAADAuth: 'true'
        }
      }
    }
    // security
    securityProfile: {
      defender: {
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceId
        securityMonitoring: {
          enabled: true
        }
      }
      imageCleaner: {
        enabled: true
        intervalHours: 168
      }
      workloadIdentity: {
        enabled: true // enable workload identity which allows pods to access Azure resources securely using the cluster's managed identities without needing to manage secrets
      }
    }
    // storage - disable all storage drivers
    storageProfile: {
      diskCSIDriver: {
        enabled: false
      }
      fileCSIDriver: {
        enabled: false
      }
      snapshotController: {
        enabled: false
      }
      blobCSIDriver: {
        enabled: false
      }
    }
    // node pools - only one system node pool
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: systemNodeCount
        vmSize: systemVmSize
        maxPods: 110
        type: 'VirtualMachineScaleSets'
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        enableAutoScaling: false
        enableNodePublicIP: false
        mode: 'System'
        osType: 'Linux'
        osSKU: 'Ubuntu'
        upgradeSettings: {
          maxSurge: '10%'
          maxUnavailable: '0'
        }
      }
    ]
  }
}

output name string = aksCluster.name
output kubeletObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output azureKeyVaultSecretsProviderIdentityObjectId string = aksCluster.properties.addonProfiles.azureKeyvaultSecretsProvider.identity.objectId
output azureKeyVaultSecretsProviderIdentityClientId string = aksCluster.properties.addonProfiles.azureKeyvaultSecretsProvider.identity.clientId
