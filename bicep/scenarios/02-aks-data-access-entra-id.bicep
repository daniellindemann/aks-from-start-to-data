targetScope = 'resourceGroup'

param projectAbbreviation string
param location string
param tags object
param suffix string

param aksEntraAdminGroupObjectIds string

var resourceAbbrs = loadJsonContent('../abbreviations-resources.json')
var scenarioName = '${projectAbbreviation}-sc2-${suffix}'

// managed identity for workload identity

module managedIdentityForWorkloadIdentity '../modules/managedIdentity.bicep' = {
  name: 'module-scenario2-mi-workload-identity-${suffix}'
  params: {
    resourceName: '${resourceAbbrs.identity}-${projectAbbreviation}-sc2-workload-${suffix}'
    location: location
    tags: tags
  }
}

// key vault

module keyVault '../modules/keyvault.bicep' = {
  name: 'module-scenario2-keyvault-${suffix}'
  params: {
    ressourceName: '${resourceAbbrs.keyVault}-${scenarioName}'
    location: location
    tags: tags
  }
}

module roleAssignmentDeployerKeyVaultAdmin '../modules/integrations/roleAssignmentDeployerKeyVaultAdmin.bicep' = {
  name: 'module-scenario2-ra-deployer-kv-${suffix}'
  params: {
    keyVaultName: keyVault.outputs.name
  }
}

module roleAssignmentManagedIdentityKeyVaultSecretsReader '../modules/integrations/roleAssignmentManagedIdentityKeyVaultSecretsReader.bicep' = {
  name: 'module-scenario2-ra-mi-kv-secrets-reader-${suffix}'
  params: {
    keyVaultName: keyVault.outputs.name
    managedIdentityObjectId: managedIdentityForWorkloadIdentity.outputs.principalId
  }
}

// sql

module sql '../modules/sqlEntraId.bicep' = {
  name: 'module-scenario2-sql-${suffix}'
  params: {
    ressourceName: '${resourceAbbrs.sqlServer}-${scenarioName}'
    location: location
    tags: tags
    suffix: suffix

    loginEntraGroupId: aksEntraAdminGroupObjectIds
  }
}

// sql to key vault integration

module addConnectionStringToKeyVault '../modules/integrations/addConnectionStringToKeyVaultEntraId.bicep' = {
  name: 'module-scenario2-cs-to-kv-${suffix}'
  params: {
    keyVaultName: keyVault.outputs.name
    sqlServerName: sql.outputs.serverName
    sqlDbName: sql.outputs.dbName
  }
}

// log analytics workspace

module logAnalyticsWorkspace '../modules/logAnalyticsWorkspace.bicep' = {
  name: 'module-scenario2-law-${suffix}'
  params: {
    ressourceName: '${resourceAbbrs.logAnalyticsWorkspace}-${scenarioName}'
    location: location
    tags: tags
  }
}

// aks

module aks '../modules/aksBasic.bicep' = {
  name: 'module-scenario2-aks-${suffix}'
  params: {
    ressourceName: '${resourceAbbrs.aks}-${scenarioName}'
    location: location
    tags: tags

    logAnalyticsWorkspaceId: logAnalyticsWorkspace.outputs.id
    entraAdminGroupObjectIds: [aksEntraAdminGroupObjectIds]
  }
}

module federationsForWorkloadIdentity '../modules/managedIdentityFederations.bicep' = {
  name: 'module-scenario2-id-federations-${suffix}'
  params: {
    managedIdentityName: managedIdentityForWorkloadIdentity.outputs.name
    oidcIssuerUrl: aks.outputs.oidcIssuerUrl
    kubernetesNamespaces: 'default' // just allow federated auth on default namespace for simplicity, but in production you would likely want to scope this down to specific namespaces used by your applications
  }
}

module roleAssignmentDeployerAksClusterAdmin '../modules/integrations/roleAssignmentDeployerAksClusterAdmin.bicep' = {
  name: 'module-scenario2-ra-deployer-aks-${suffix}'
  params: {
    aksClusterName: aks.outputs.name
  }
}
