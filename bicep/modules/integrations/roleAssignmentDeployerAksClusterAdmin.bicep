param aksClusterName string

var deployerPrincipalId = deployer().objectId
var aksRbacClusterAdminRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b') // role name: Azure Kubernetes Service RBAC Cluster Admin

resource aksCluster 'Microsoft.ContainerService/managedClusters@2026-01-01' existing = {
  name: aksClusterName
}

resource keyVaultSecretUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, deployerPrincipalId, aksRbacClusterAdminRole)
  scope: aksCluster
  properties: {
    principalId: deployerPrincipalId
    roleDefinitionId: aksRbacClusterAdminRole
    principalType: 'User'
  }
}
