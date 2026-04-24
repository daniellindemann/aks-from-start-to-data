param ressourceName string
param location string
param tags object
param suffix string

@description('ID of the Entra group that will be the administrator of the SQL server')
param loginEntraGroupId string

var resourceAbbrs = loadJsonContent('../abbreviations-resources.json')

resource sqlServer 'Microsoft.Sql/servers@2023-08-01' = {
  name: ressourceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    version: '12.0'
    publicNetworkAccess: 'Enabled'
    administrators: {
      azureADOnlyAuthentication: true
      tenantId: tenant().tenantId
      principalType: 'Group'
      sid: loginEntraGroupId
      login: loginEntraGroupId
      administratorType: 'ActiveDirectory'
    }
  }
}

resource sqlFirewallSettings 'Microsoft.Sql/servers/firewallRules@2023-08-01' = {
  parent: sqlServer
  name: 'azure-services'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource sqlDb 'Microsoft.Sql/servers/databases@2023-08-01' = {
  parent: sqlServer
  name: '${resourceAbbrs.sqlDatabase}-beer-rating-${suffix}'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    zoneRedundant: false
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: 'Local'
  }
}

output serverName string = sqlServer.name
output dbName string = sqlDb.name
output sqlServerPrincipalId string = sqlServer.identity.principalId
