@description('Name of the Key Vault to which the role assignment will be applied.')
param keyVaultName string

@description('Object Id of the managed identity to which the role assignment will be applied.')
param managedIdentityObjectId string

var keyVaultSecretsUserRole = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4633458b-17de-408a-b874-0445c86b69e6'
) // role name: Key Vault Secrets User

resource keyVault 'Microsoft.KeyVault/vaults@2025-05-01' existing = {
  name: keyVaultName
}

resource roleAssignment_keyVault_keyVaultSecretsUserRole_workloadIdentity 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentityObjectId, keyVaultSecretsUserRole)
  scope: keyVault
  properties: {
    description: 'Allows the workload identity to access key vault secrets'
    roleDefinitionId: keyVaultSecretsUserRole
    principalId: managedIdentityObjectId
    principalType: 'ServicePrincipal'
  }
}
