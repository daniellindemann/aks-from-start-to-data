#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
resourceGroupName=${1:?Parameter resourceGroupName is required}
firewallRuleName='script-client-public-ip'
deleteTimeout='300s'

for tool in az jq kubectl kubelogin helm; do
    if ! command -v "$tool" >/dev/null; then
        echo "Required tool '${tool}' is not installed." >&2
        exit 1
    fi
done

resourceGroupJsonData=$(az resource list --resource-group "$resourceGroupName" -o json)
aksName=$(jq -er '[.[] | select(.type == "Microsoft.ContainerService/managedClusters")] |
    if length == 1 then .[0].name else error("Expected exactly one AKS cluster") end' <<< "$resourceGroupJsonData")
sqlServerName=$(jq -er '[.[] | select(.type == "Microsoft.Sql/servers")] |
    if length == 1 then .[0].name else error("Expected exactly one SQL server") end' <<< "$resourceGroupJsonData")
workloadIdentityName=$(jq -r '[.[] | select(.type == "Microsoft.ManagedIdentity/userAssignedIdentities")] |
    if length == 0 then "" elif length == 1 then .[0].name
    else error("Expected at most one workload identity") end' <<< "$resourceGroupJsonData")

if [[ -n "$workloadIdentityName" ]]; then
    for tool in sqlcmd curl; do
        if ! command -v "$tool" >/dev/null; then
            echo "Required tool '${tool}' is not installed." >&2
            exit 1
        fi
    done
    sqlDbName=$(jq -er --arg server "$sqlServerName" '[.[] |
        select(.type == "Microsoft.Sql/servers/databases" and
            (.name | startswith($server + "/sqldb-beer-rating")))] |
        if length == 1 then .[0].name | split("/")[1]
        else error("Expected exactly one beer-rating SQL database") end' <<< "$resourceGroupJsonData")
fi

# Use isolated credentials so the reset cannot target the caller's current context.
export KUBECONFIG
KUBECONFIG=$(mktemp)
removeFirewallRule=false
cleanup() {
    local status=$?
    trap - EXIT
    if [[ "$removeFirewallRule" == true ]]; then
        echo "Deleting SQL firewall rule '${firewallRuleName}'"
        if ! az sql server firewall-rule delete --resource-group "$resourceGroupName" \
            --server "$sqlServerName" --name "$firewallRuleName"; then
            echo "Failed to delete SQL client firewall rule." >&2
            status=1
        fi
    fi
    rm -f -- "$KUBECONFIG"
    exit "$status"
}
trap cleanup EXIT

echo "Get credentials for AKS cluster '${aksName}' in '${resourceGroupName}'"
az aks get-credentials --resource-group "$resourceGroupName" --name "$aksName" \
    --file "$KUBECONFIG" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes

delete_existing_resources() {
    local resourceNames
    local -a resources
    resourceNames=$(kubectl get "$@" --namespace default --ignore-not-found -o name)
    if [[ -n "$resourceNames" ]]; then
        mapfile -t resources <<< "$resourceNames"
        # Foreground cascade waits until dependents (e.g. ReplicaSets, Pods) are removed too.
        kubectl delete "${resources[@]}" --namespace default --ignore-not-found \
            --cascade=foreground --wait=true --timeout="$deleteTimeout"
    fi
}

echo "Deleting deployments, jobs, and setup test pods in namespace 'default'"
delete_existing_resources deployments,jobs
delete_existing_resources pods test-busybox-keyvault-access sql-test-connection

echo "Deleting ingress configuration and SecretProviderClasses in namespace 'default'"
delete_existing_resources ingresses.networking.k8s.io
apiResources=$(kubectl api-resources --verbs=list,delete --namespaced -o name)
while IFS= read -r resource; do
    case "$resource" in
        secretproviderclasses.secrets-store.csi.x-k8s.io|*.traefik.io|*.traefik.containo.us)
            delete_existing_resources "$resource"
            ;;
    esac
done <<< "$apiResources"

echo "Deleting service accounts except 'default' and services except 'kubernetes'"
delete_existing_resources serviceaccounts --field-selector='metadata.name!=default'
delete_existing_resources services --field-selector='metadata.name!=kubernetes'

echo "Uninstalling Traefik and deleting its namespace"
traefikNamespace=$(kubectl get namespace traefik --ignore-not-found -o name)
if [[ -n "$traefikNamespace" ]]; then
    helm uninstall traefik --namespace traefik --ignore-not-found \
        --cascade foreground --wait --timeout "$deleteTimeout"
    kubectl delete namespace traefik --ignore-not-found --wait=true --timeout="$deleteTimeout"
else
    echo "Traefik namespace is already absent."
fi

firewallRules=$(az sql server firewall-rule list --resource-group "$resourceGroupName" \
    --server "$sqlServerName" -o json)
firewallRuleExists=$(jq -r --arg name "$firewallRuleName" 'any(.[]; .name == $name)' <<< "$firewallRules")
if [[ "$firewallRuleExists" == true ]]; then
    removeFirewallRule=true
fi

if [[ -n "$workloadIdentityName" ]]; then
    echo "Removing SQL permissions for workload identity '${workloadIdentityName}'"
    publicIp=$(curl --fail --silent --show-error --ipv4 https://ifconfig.io/ip)
    # Reopen access for SQL cleanup, including when a previous reset removed the rule.
    removeFirewallRule=true
    az sql server firewall-rule create --resource-group "$resourceGroupName" \
        --server "$sqlServerName" --name "$firewallRuleName" \
        --start-ip-address "$publicIp" --end-ip-address "$publicIp" -o none
    sqlcmd -S "${sqlServerName}.database.windows.net" -d "$sqlDbName" \
        --authentication-method=ActiveDirectoryDefault -b \
        -v MemberName="$workloadIdentityName" -i "$script_dir/../sql/remove-sql-permissions.sql"
else
    echo "No workload identity found; skipping SQL permission removal."
fi

if [[ "$removeFirewallRule" == true ]]; then
    echo "Deleting SQL firewall rule '${firewallRuleName}'"
    az sql server firewall-rule delete --resource-group "$resourceGroupName" \
        --server "$sqlServerName" --name "$firewallRuleName"
    removeFirewallRule=false
fi

echo "Cluster resources reset; Azure infrastructure and database contents retained."
