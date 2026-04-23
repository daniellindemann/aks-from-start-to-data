targetScope = 'resourceGroup'

param projectAbbreviation string
param location string
param tags object
param suffix string

param sqlAdminUsername string
@secure()
param sqlAdminPassword string

param aksEntraAdminGroupObjectIds string

var resourceAbbrs = loadJsonContent('../abbreviations-resources.json')
var scenarioName = '${projectAbbreviation}-sc1-${suffix}'

// key vault

module keyVault '../modules/keyvault.bicep' = {
  name: 'module-scenario1-keyvault-${suffix}'
  params: {
    ressourceName: '${resourceAbbrs.keyVault}-${scenarioName}'
    location: location
    tags: tags
  }
}

module roleAssignmentDeployerKeyVaultAdmin '../modules/integrations/roleAssignmentDeployerKeyVaultAdmin.bicep' = {
  name: 'module-scenario1-ra-deployer-keyvault-${suffix}'
  params: {
    keyVaultName: keyVault.outputs.name
  }
}

// sql

module sql '../modules/sqlAdminPassword.bicep' = {
  name: 'module-scenario1-sql-${suffix}'
  params: {
    ressourceName: '${resourceAbbrs.sqlDatabase}-${scenarioName}'
    location: location
    tags: tags
    suffix: suffix

    sqlAdminUsername: sqlAdminUsername
    sqlAdminPassword: sqlAdminPassword
  }
}

// sql to key vault integration

module addConnectionStringToKeyVault '../modules/integrations/addConnectionStringToKeyVaultUsernamePassword.bicep' = {
  name: 'module-scenario1-cs-to-kv-${suffix}'
  params: {
    keyVaultName: keyVault.outputs.name
    sqlServerName: sql.outputs.serverName
    sqlDbName: sql.outputs.dbName
    sqlAdminUsername: sqlAdminUsername
    sqlAdminPassword: sqlAdminPassword
  }
}

// log analytics workspace

module logAnalyticsWorkspace '../modules/logAnalyticsWorkspace.bicep' = {
  name: 'module-scenario1-law-${suffix}'
  params: {
    ressourceName: '${resourceAbbrs.logAnalyticsWorkspace}-${scenarioName}'
    location: location
    tags: tags
  }
}

// aks

module aks '../modules/aksBasic.bicep' = {
  name: 'module-scenario1-aks-${suffix}'
  params: {
    ressourceName: '${resourceAbbrs.aks}-${scenarioName}'
    location: location
    tags: tags

    logAnalyticsWorkspaceId: logAnalyticsWorkspace.outputs.id
    entraAdminGroupObjectIds: [aksEntraAdminGroupObjectIds]
  }
}

module roleAssignmentDeployerAksClusterAdmin '../modules/integrations/roleAssignmentDeployerAksClusterAdmin.bicep' = {
  name: 'module-scenario1-ra-deployer-aks-${suffix}'
  params: {
    aksClusterName: aks.outputs.name
  }
}
