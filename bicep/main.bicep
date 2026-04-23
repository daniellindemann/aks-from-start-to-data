targetScope = 'subscription'

param projectAbbreviation string = 'afstd'
param location string = deployment().location
param tags object = {}

@minValue(3)
@maxValue(13)
param suffixLength int = 8

param skipScenario1BasicAks bool = false
param skipScenario2AksWithDataViaEntraAuth bool = false

param sqlAdminUsername string = 'sqladmin'
@secure()
param sqlAdminPassword string = 'P@ssw0rd1234!'

@description('List of Entra ID group object IDs that should be added as AKS admins')
param aksEntraAdminGroupObjectIds string

var suffix = substring(uniqueString(subscription().id), 0, suffixLength)
var allTags = union(
  {
    environment: 'demo'
    project: 'aks-from-start-to-data'
    deployer: deployer().userPrincipalName
  },
  tags
)
var aksShutdownTags = {
  'auto-aks-start-at-utc': '05:00' // 05:00 UTC = 06:00 CET = 07:00 CEST
  'auto-aks-stop-at-utc': '17:00' // 17:00 UTC = 18:00 CET = 19:00 CEST
  'auto-aks-days': 'Mon,Tue,Wed,Thu,Fri,Sat,Sun'
}

//
// Scenario 1: Basic AKS with SQL using username and password
//

resource rgSimpleAks 'Microsoft.Resources/resourceGroups@2025-04-01' = if (!skipScenario1BasicAks) {
  name: 'rg-${projectAbbreviation}-scenario1-basic-aks-${suffix}'
  location: location
  tags: allTags
}

module scenario1BasicAks 'scenarios/01-basic-aks.bicep' = if (!skipScenario1BasicAks) {
  name: 'module-${projectAbbreviation}-scenario1-basic-aks-${suffix}'
  scope: rgSimpleAks
  params: {
    projectAbbreviation: projectAbbreviation
    location: location
    tags: union(allTags, aksShutdownTags)
    suffix: suffix

    sqlAdminUsername: sqlAdminUsername
    sqlAdminPassword: sqlAdminPassword

    aksEntraAdminGroupObjectIds: aksEntraAdminGroupObjectIds
  }
}

//
// Scenario 2: AKS with SQL using Entra ID authentication
//

resource rgAksWithDataViaEntraAuth 'Microsoft.Resources/resourceGroups@2025-04-01' = if (!skipScenario2AksWithDataViaEntraAuth) {
  name: 'rg-${projectAbbreviation}-scenario2-aks-with-data-via-entra-auth-${suffix}'
  location: location
  tags: allTags
}

module scenario2AksWithDataViaEntraAuth 'scenarios/02-aks-data-access-entra-id.bicep' = if (!skipScenario2AksWithDataViaEntraAuth) {
  name: 'module-${projectAbbreviation}-scenario2-aks-with-data-via-entra-auth-${suffix}'
  scope: rgAksWithDataViaEntraAuth
  params: {
    projectAbbreviation: projectAbbreviation
    location: location
    tags: union(allTags, aksShutdownTags)
    suffix: suffix

    aksEntraAdminGroupObjectIds: aksEntraAdminGroupObjectIds
  }
}
