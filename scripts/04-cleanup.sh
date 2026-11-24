#!/usr/bin/env bash

set -euo pipefail

script_dir=$(dirname "$0")

# script variables
azure_tag_key='project'
azure_tag_value='aks-from-start-to-data'

# get resource groups with tag
echo "🔎 Get resource groups with tag '${azure_tag_key}=${azure_tag_value}'"
resourceGroupsJson=$(az group list --tag $azure_tag_key=$azure_tag_value --query '[?!starts_with(name, `MC_`)].name' -o json)
echo "🐕 Retrieved resource groups"

# get key vaults with tag
echo "🔎 Get key vaults with tag '${azure_tag_key}=${azure_tag_value}'"
keyVaultsJson=$(az keyvault list --query "[?tags.${azure_tag_key}=='${azure_tag_value}'].name" -o json)
echo "🐕 Retrieved key vaults"

# delete resource groups
echo -e "\033[1m🔥  Deleting resource groups\033[0m"
for resourceGroupName in $(echo "$resourceGroupsJson" | jq -r '.[]'); do
  echo "🗑️  Deleting resource group '${resourceGroupName}'"
  az group delete --name "$resourceGroupName" --yes
done
echo "Resource groups deleted"

# purge key vaults
echo -e "\033[1m🔫  Purging key vaults\033[0m"
for keyVaultName in $(echo "$keyVaultsJson" | jq -r '.[]'); do
  echo "🗑️  Purging key vault '${keyVaultName}'"
  az keyvault purge --name "$keyVaultName"
done
echo "Key vaults purged"

echo "🧹 Cleanup completed"
