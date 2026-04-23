@description('Name of the user-assigned managed identity to be used for identity federation.')
param managedIdentityName string

@description('OIDC issuer URL used for identity federation.')
param oidcIssuerUrl string

@description('The namespaces in the AKS cluster where workload identity federation should be enabled.')
param kubernetesNamespaces string

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: managedIdentityName
}

@description('Add federations for service accounts in the specified namespaces to the managed identity.')
resource federations 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = {
  name: managedIdentity.name
  parent: managedIdentity
  properties: {
    issuer: oidcIssuerUrl
    subject: 'system:serviceaccount:${kubernetesNamespaces}:${managedIdentity.name}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}
