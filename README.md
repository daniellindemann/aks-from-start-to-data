# aks-from-start-to-data

This project shows different evolutions of aks clusters with data connections.

## Deployment

> ℹ️ **Info**  
> The setup steps require [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/).  
> Install Azure CLI as described on https://learn.microsoft.com/en-us/cli/azure/install-azure-cli and run `az login` to authenticate.

> ℹ️ **Info**  
> All Azure resource creating commands use the region *Poland Central*. Change it, if required.

> ℹ️ **Info**  
> Commands shown are bash commands, you may need to change them, if you are using *PowerShell*.

### 1. Prerequisite: Create AKS Administrator Group

Create group AKS Admins:

```bash
az ad group create \
    --display-name 'AKS Admins' \
    --mail-nickname aksadmins \
    --description 'Administrators of AKS Clusters are placed in this group' \
    --query '{objectId: id, displayName: displayName, mailNickname: mailNickname, description: description}' \
    -o table
```

Add current user to owners and mebers list

```bash
az ad group owner add \
    --group 'AKS Admins' \
    --owner-object-id $(az ad signed-in-user show --query id --output tsv)
az ad group member add \
    --group 'AKS Admins' \
    --member-id $(az ad signed-in-user show --query id --output tsv)
```

### 2. Deploy Azure resources

> ⚠️ **Warning**  
> The code uses the previously created *AKS Admins* group. If you created the group with another name, replace the name group of in the parameter assignment of `aksEntraAdminGroupObjectIds` in the following command.

```bash
az deployment sub create \
    --name="aks-from-start-to-data-$(date +%Y%m%d%H%M%S)" \
    --location polandcentral \
    --template-file bicep/main.bicep \
    --parameters aksEntraAdminGroupObjectIds=$(az ad group show -g 'AKS Admins' --query id -o tsv)
```

### 3. Apply app resources

#### With basic AKS configuration

1. Get Azure resource names
    - Get AKS resource name from listing: `az aks list -o table --query '[*].{name: name, location: location, resourceGroup: resourceGroup, kubernetesVersion: kubernetesVersion}'`
    - Get Key Vault name from listing: `az keyvault list -o table --query '[*].{name: name, location: location, resourceGroup: resourceGroup}'`
2. Execute configuration script [`scripts/01-configure-aks.sh`](scripts/01-configure-aks.sh)

    ```bash
    scripts/01-configure-aks.sh <AKS-Name> <Key-Vault-Name>
    ```

---


- was braucht der aks
  - workload identity
  - public network access
  - rbac enabled inkl. azure rbac und permissions
  - netzwerk so standard wie möglich
  - standard load balancing
  - 
