param ressourceName string
param location string
param tags object
param suffix string

param sqlAdminUsername string
@secure()
param sqlAdminPassword string

var resourceAbbrs = loadJsonContent('../abbreviations-resources.json')

resource sqlServer 'Microsoft.Sql/servers@2023-08-01' = {
  name: ressourceName
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
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

@secure()
output adminUsername string = sqlAdminUsername
@secure()
output adminPassword string = sqlAdminPassword
