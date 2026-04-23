param keyVaultName string

var deployerPrincipalId = deployer().objectId
var keyVaultAdministratorRole = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '00482a5a-887f-4fb3-b363-3b7fe8e74483'
) // role name: Key Vault Administrator

resource keyVault 'Microsoft.KeyVault/vaults@2025-05-01' existing = {
  name: keyVaultName
}

resource keyVaultSecretUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, deployerPrincipalId, keyVaultAdministratorRole)
  scope: keyVault
  properties: {
    principalId: deployerPrincipalId
    roleDefinitionId: keyVaultAdministratorRole
    principalType: 'User'
  }
}
