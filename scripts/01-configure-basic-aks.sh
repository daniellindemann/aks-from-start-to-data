#!/usr/bin/env bash

set -euo pipefail

script_dir=$(dirname "$0")

# parameters
aksName=${1:?Parameter aksName is required}
keyVaultName=${2:?Parameter keyVaultName is required}

# script variables
backend_image='daniellindemann/beer-rating-backend:10'
frontend_image='daniellindemann/beer-rating-frontend:10'
console_image='daniellindemann/beer-rating-console-beerquotes:10'
migrations_image='daniellindemann/beer-rating-backend-migrations:10'
secret_name_connection_string='connection-string-beer-rating'

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

# get connection string to database from key vault - NOT BEST PRACTICE
connectionStringSecret=$(az keyvault secret show --name ${secret_name_connection_string} --vault-name ${keyvault_name} --query value -o tsv)

# apply migrations using a job
echo "Apply EF migrations using a Kubernetes job"
migrationsJobYaml="$(cat "$script_dir/../k8s/01-basic-aks/job-apply-migrations.yaml")"
replacedMigrationImage=$(echo "$migrationsJobYaml" | yq ".spec.template.spec.containers[0].image = \"${migrations_image}\"")
replacedMigrationConnectionString=$(echo "$replacedMigrationImage" | yq "(.spec.template.spec.containers[] | select(.name == \"migrations\") | .env[] | select(.name == \"CONNECTION_STRING\") | .value) = \"${connectionStringSecret}\"")
echo "$replacedMigrationConnectionString" | kubectl apply -f -
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
backendDeploymentYaml="$(cat "$script_dir/../k8s/01-basic-aks/deployment-backend.yaml")"
replacedBackendImage=$(echo "$backendDeploymentYaml" | yq ".spec.template.spec.containers[0].image = \"${backend_image}\"")
replacedConsoleImage=$(echo "$replacedBackendImage" | yq ".spec.template.spec.containers[1].image = \"${console_image}\"")
replacedBackendConnectionString=$(echo "$replacedConsoleImage" | yq "(.spec.template.spec.containers[] | select(.name == \"beer-rating-backend\") | .env[] | select(.name == \"ConnectionStrings__Beer\") | .value) = \"${connectionStringSecret}\"")
echo "$replacedBackendConnectionString" | kubectl apply -f -
kubectl apply -f $script_dir/../k8s/shared/service-backend.yaml
# ---
# replace image name in the deployment yaml file of the frontend with the one from container registry
frontendDeploymentYaml="$(cat "$script_dir/../k8s/01-basic-aks/deployment-frontend.yaml")"
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
