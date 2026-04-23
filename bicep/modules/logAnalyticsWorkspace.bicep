param ressourceName string
param location string
param tags object

@description('Daily cap in GB. Set to `-1` to disable the daily cap.')
param dailyCapQuotaInGb int = 3

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: ressourceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    workspaceCapping: {
      dailyQuotaGb: dailyCapQuotaInGb
    }
  }
}

output name string = logAnalyticsWorkspace.name
output id string = logAnalyticsWorkspace.id
