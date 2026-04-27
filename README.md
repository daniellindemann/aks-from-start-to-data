# aks-from-start-to-data

This project shows different evolutions of aks clusters with data connections.

## Deployment

> ℹ️ **Info**  
> The setup steps require [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/).  
> Install Azure CLI as described on https://learn.microsoft.com/en-us/cli/azure/install-azure-cli and run `az login` to authenticate.  
> *Using the Dev Container, the Azure CLI is already installed*

> ℹ️ **Info** 
> Kubernetes Tools are required for automated setup:
> - [kubectl](https://kubernetes.io/docs/tasks/tools/) (or install via `az aks install-cli`)
> - [kubelogin](https://github.com/Azure/kubelogin) (or install via `az aks install-cli`)
> - [helm](https://helm.sh)
> - [sqlcmd](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-download-install?tabs=linux)
> 
> *Using the Dev Container, these tools are already installed*

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

1. 1Get resource group using this command: `az group list --query "[?contains(name, 'afstd-scenario1')].name" -o tsv`
2. Execute configuration script [`scripts/01-configure-basic-aks.sh`](scripts/01-configure-basic-aks.sh)

    ```bash
    scripts/01-configure-basic-aks.sh <Resource-Group-Name>
    ```

> 💡 Do it in one command:
> ```bash
> scripts/01-configure-basic-aks.sh $(az group list --query "[?contains(name, 'afstd-scenario1')].name" -o tsv)
> ```

#### With managed identity and AKS workload identity

1. Ensure the SQL server system-assigned identity has `Directory Reader` role in Entra ID
    - To get managed identity name use command `az sql server list --query "[?contains(name, 'afstd-sc2')].name" -o tsv`
    - Use an Entra ID Account with enough permissions, like `Global Administrator`, to set the role
2. Get resource group using this command: `az group list --query "[?contains(name, 'afstd-scenario2')].name" -o tsv`
3. Execute configuration script [`scripts/02-configure-aks-data-access-entra-id.sh`](scripts/02-configure-aks-data-access-entra-id.sh)

    ```bash
    scripts/02-configure-aks-data-access-entra-id.sh <Resource-Group-Name>
    ```

> 💡 Do it in one command:
> ```bash
> scripts/02-configure-aks-data-access-entra-id.sh $(az group list --query "[?contains(name, 'afstd-scenario2')].name" -o tsv)
> ```

## Demos

See Demo playbook: [Demos.md](Demos.md)

## Clean-up

Run the cleanup script

```bash
scripts/03-cleanup.sh
```
