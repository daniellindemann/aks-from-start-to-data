#!/usr/bin/env bash

set -euo pipefail

script_dir=$(dirname "$0")

# parameters
resourceGroupName=${1:?Parameter resourceGroupName is required}

# script variables
backend_image='daniellindemann/beer-rating-backend:10'
frontend_image='daniellindemann/beer-rating-frontend:10'
console_image='daniellindemann/beer-rating-console-beerquotes:10'
migrations_image='daniellindemann/beer-rating-backend-migrations:10'
secret_name_connection_string='connection-string-beer-rating'

# retrieve resource names from resource group
resourceGroupJsonData=$(az resource list --resource-group $resourceGroupName -o json)
aksName=$(echo "$resourceGroupJsonData" | jq -r '.[] | select(.type == "Microsoft.ContainerService/managedClusters") | .name')
keyVaultName=$(echo "$resourceGroupJsonData" | jq -r '.[] | select(.type == "Microsoft.KeyVault/vaults") | .name')
workloadIdentityName=$(echo "$resourceGroupJsonData" | jq -r '.[] | select(.type == "Microsoft.ManagedIdentity/userAssignedIdentities") | .name')
sqlServerName=$(echo "$resourceGroupJsonData" | jq -r '.[] | select(.type == "Microsoft.Sql/servers") | .name')
sqlDbName=$(echo "$resourceGroupJsonData" | jq -r '.[] | select(.type == "Microsoft.Sql/servers/databases" and (.name | contains("sqldb-beer-rating"))) | .name | split("/")[1]')

# get aks info
echo "🔎 Get AKS cluster named '${aksName}'"
aks_json_data=$(az aks list --query "[?name == '${aksName}'].{name: name, resourceGroup: resourceGroup, keyVaultvIdentity: addonProfiles.azureKeyvaultSecretsProvider.identity}[0]" -o json)
aks_name=$(echo $aks_json_data | jq -r '.name')
aks_resourceGroup=$(echo $aks_json_data | jq -r '.resourceGroup')
aks_keyVaultIdentity_clientId=$(echo $aks_json_data | jq -r '.keyVaultvIdentity.clientId')
echo "🐕 Retrieved '${aks_name}' on resource group '${aks_resourceGroup}'"

# get key vault info
echo "🔎 Get key vault named '${keyVaultName}'"
keyvault_json_data=$(az keyvault list --query "[?name == '${keyVaultName}'].{name: name, resourceGroup: resourceGroup}[0]" -o json)
keyvault_name=$(echo $keyvault_json_data | jq -r '.name')
keyvault_resourceGroup=$(echo $keyvault_json_data | jq -r '.resourceGroup')
echo "🐕 Retrieved '${keyvault_name}' on resource group '${keyvault_resourceGroup}'"

# get tools
echo "Installing aks cli tools (kubectl, kubelogin)"
if [ ! -x /usr/local/bin/kubelogin ]; then
  sudo az aks install-cli
fi
echo "Tools installed"

# install helm
echo "Installing helm"
if [ ! -x /usr/local/bin/helm ]; then
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 \
    && chmod 700 get_helm.sh \
    && ./get_helm.sh \
    && rm get_helm.sh
fi
echo "Helm installed"

# retrieve credentials for current user
echo "Get AKS credentials for current user '$(az account show --query 'user.name' -o tsv)'"
tenantId=$(az account show --query 'tenantId' -o tsv)
az aks get-credentials --resource-group $aks_resourceGroup --name $aks_name --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
echo "Credentials retrieved"

# check connection by retrieving nodes
echo "Get AKS nodes to ensure connection works"
kubectl get nodes
echo "Nodes retrieved"

# install traefik ingress controller using helm
echo "Installing traefik ingress controller using helm"
# install traefik in traefik namespace with default config
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik --create-namespace --namespace traefik
# get public ip of ingress controller
# wait until public ip is assigned
while true; do
    ingressPublicIp=$(kubectl get services \
        --namespace traefik \
        traefik \
        --output jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [[ -n "$ingressPublicIp" && $(grep -o "\." <<< "$ingressPublicIp" | wc -l) -eq 3 ]]; then
        echo "Ingress controller public ip is '$ingressPublicIp'"
        break
    fi
    sleep 5
done
echo "Ingress controller traefik installed"

# create service account for workload identity
echo "Create service account for workload identity"
managedIdentityClientId=$(az identity show --name $workloadIdentityName --resource-group $resourceGroupName --query 'clientId' -o tsv)
serviceAccountYaml="$(cat "$script_dir/../k8s/02-configure-aks-data-access-entra-id/serviceAccount-workloadidentity.yaml")"
replacedManagedIdentityClientId=$(echo "$serviceAccountYaml" | yq ".metadata.annotations[\"azure.workload.identity/client-id\"] = \"${managedIdentityClientId}\"")
replacedManagedIdentityName=$(echo "$replacedManagedIdentityClientId" | yq ".metadata.name = \"${workloadIdentityName}\"")
echo "$replacedManagedIdentityName" | kubectl apply -f -
echo "Service Account for workload identity created"

# create secret provider class to retrieve secrets from key vault using workload identity
echo "Create SecretProviderClass to retrieve secrets from key vault using workload identity"
secretProviderClassYaml="$(cat "$script_dir/../k8s/02-configure-aks-data-access-entra-id/secretProviderClass-backend-secrets.yaml")"
replacedClientId=$(echo "$secretProviderClassYaml" | yq ".spec.parameters.clientID = \"${managedIdentityClientId}\"")
replacedKeyVaultName=$(echo "$replacedClientId" | yq ".spec.parameters.keyvaultName = \"${keyVaultName}\"")
replacedTenantId=$(echo "$replacedKeyVaultName" | yq ".spec.parameters.tenantId = \"${tenantId}\"")
echo "$replacedTenantId" | kubectl apply -f -
echo "SecretProviderClass created"

# create a test busybox pod to test retrieval of secrets from key vault using workload identity
echo "Create a test busybox pod to test retrieval of secrets from key vault using workload identity"
busyboxYaml="$(cat "$script_dir/../k8s/02-configure-aks-data-access-entra-id/pod-busybox-keyvault-access.yaml")"
busyBoxYamlServiceAccountReplaced=$(echo "$busyboxYaml" | yq ".spec.serviceAccountName = \"${workloadIdentityName}\"")
echo "$busyBoxYamlServiceAccountReplaced" | kubectl apply -f -
echo "Test busybox pod created"

echo "Add firewall rule to allow sql connection from client"
publicIp=$(curl -s https://ifconfig.io)
az sql server firewall-rule create \
    -g $resourceGroupName \
    -s $sqlServerName \
    -n script-client-public-ip \
    --start-ip-address $publicIp \
    --end-ip-address $publicIp \
    -o table
echo "Firewall rule added for ip"

# Grant permissions to the SQL server for the workload identity
echo "Grant permissions to the SQL server for the workload identity"
sqlcmd -S "${sqlServerName}.database.windows.net" \
  -d "${sqlDbName}" \
  --authentication-method=ActiveDirectoryDefault \
  -v MemberName="${workloadIdentityName}" \
  -i "$script_dir/../sql/add-sql-permissions.sql"
sqlcmd -S "${sqlServerName}.database.windows.net" \
  -d "${sqlDbName}" \
  --authentication-method=ActiveDirectoryDefault \
  -Q "SELECT r.name AS RoleName, m.name AS UserName, m.type_desc AS PrincipalType FROM sys.database_role_members rm JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id WHERE r.type = 'R' AND m.name = '${workloadIdentityName}' ORDER BY r.name, m.name;"
echo "Permissions granted to SQL server for workload identity"

# test sql connection with workload identity
echo "Create a test sql client pod to test sql connection with workload identity"
sqlConnectionYaml="$(cat "$script_dir/../k8s/02-configure-aks-data-access-entra-id/pod-sqlconnection.yaml")"
sqlConnectionYamlServiceAccountReplaced=$(echo "$sqlConnectionYaml" | yq ".spec.serviceAccountName = \"${workloadIdentityName}\"")
echo "$sqlConnectionYamlServiceAccountReplaced" | kubectl apply -f -
echo "Test sql client pod created"

# apply migrations using a job
echo "Apply EF migrations using a Kubernetes job"
migrationsJobYaml="$(cat "$script_dir/../k8s/02-configure-aks-data-access-entra-id/job-apply-migrations.yaml")"
replacedMigrationImage=$(echo "$migrationsJobYaml" | yq ".spec.template.spec.containers[0].image = \"${migrations_image}\"")
replacedMigrationServiceAccount=$(echo "$replacedMigrationImage" | yq ".spec.template.spec.serviceAccountName = \"${workloadIdentityName}\"")
echo "$replacedMigrationServiceAccount" | kubectl apply -f -
# loop until the job is completed
while true; do
    jobStatus=$(kubectl get job apply-ef-migrations -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')
    if [[ "$jobStatus" == "True" ]]; then
        echo "Migrations job completed successfully"
        break
    fi
    sleep 5
done
echo "Migrations applied"

# deploy sample app
echo "Apply deployments and services"
# replace the image name in the deployment yaml file of the backend with the one from container registry
backendDeploymentYaml="$(cat "$script_dir/../k8s/02-configure-aks-data-access-entra-id/deployment-backend.yaml")"
replacedBackendImage=$(echo "$backendDeploymentYaml" | yq ".spec.template.spec.containers[0].image = \"${backend_image}\"")
replacedConsoleImage=$(echo "$replacedBackendImage" | yq ".spec.template.spec.containers[1].image = \"${console_image}\"")
replacedBackendServiceAccount=$(echo "$replacedConsoleImage" | yq ".spec.template.spec.serviceAccountName = \"${workloadIdentityName}\"")
echo "$replacedBackendServiceAccount" | kubectl apply -f -
kubectl apply -f $script_dir/../k8s/shared/service-backend.yaml
# ---
# replace image name in the deployment yaml file of the frontend with the one from container registry
frontendDeploymentYaml="$(cat "$script_dir/../k8s/02-configure-aks-data-access-entra-id/deployment-frontend.yaml")"
replacedFrontendImage=$(echo "$frontendDeploymentYaml" | yq ".spec.template.spec.containers[0].image = \"${frontend_image}\"")
echo "$replacedFrontendImage" | kubectl apply -f -
kubectl apply -f $script_dir/../k8s/shared/service-frontend.yaml
echo "Deployments and services applied"

# configure ingress
echo "Apply ingress rules"
kubectl apply -f $script_dir/../k8s/shared/ingress-frontend.yaml
echo "Ingress rules applied"

# kubernetes info
kubectl get pods,svc,ingress

# output access info
echo "Everything applied successfully"
echo "> You can access the application on http://${ingressPublicIp} or http://${ingressPublicIp}.nip.io"
echo "> Use ip ${ingressPublicIp} to create a DNS A record for your custom domain"
