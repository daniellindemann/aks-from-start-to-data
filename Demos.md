# Demos

# Prep

- [Azure Ressourcen deployen](README.md#2-deploy-azure-resources)
- Kubernetes Tools installieren: `az aks install-cli`

## AKS + SQL DB über Portal erstellen

- [ ] Zeige AKS Erstellung über Portal
    - AKS zeigen
- [ ] Azure SQL über Portal
    - SQL zeigen

## Nodes prüfen

```bash
kubectl get nodes -o wide
```

## Applikationen deployen

### Pod erstellen

- Mit `kubectl` einen `daniellindemann/sonic` Pod erstellen

```bash
kubectl run sonic --image=daniellindemann/sonic
```

- Prüfe, ob der Pod erfolgreich gestartet wurde

```bash
kubectl get pods
```

- Prüfe, ob Sonic läuft

```bash
kubectl exec sonic -- node -v
```

- Port-forward Sonic Pod auf lokale Maschine

```bash
kubectl port-forward pod/sonic 8800:8080
```

- Zugriff auf http://localhost:8800

- Pod löschen, weil nur Single-Instance

```bash
kubectl delete pod sonic
```

### Deployment erstellen

#### Option A

- Prüfen, was auf dem Kubernetes Cluster läuft

```bash
kubectl get deployments
kubectl get replicasets
kubectl get pod -o wide
```

- Deployment mit `6` Replicas erstellen

```bash
kubectl create deployment sonic --image=daniellindemann/sonic --replicas=6 --port=8080
```

- Testen durch pod löschen --> Neuer Pod wird erstellt

```bash
kubectl delete pod sonic-...
```

#### Option B

- Prüfen, was auf dem Kubernetes Cluster läuft

```bash
kubectl get deployments
kubectl get replicasets
kubectl get pod -o wide
```

- Erstelle eine YAML-Datei durch `kubectl`

```bash
kubectl create deployment sonic --image=daniellindemann/sonic --replicas=6 --port=8080 -o yaml --dry-run=client > deployment-sonic.yaml
```

- YAML-Datei mit editor überprüfen

- `Apply` YAML-Datei mit `kubectl`

```bash
kubectl apply -f deployment-sonic.yaml
```

- Testen durch pod löschen --> Neuer Pod wird erstellt

```bash
kubectl delete pod sonic-...
```


### Service erstellen

- Service für Deployment bereitstellen

```bash
kubectl expose deployment sonic --port=8800 --target-port=8080
kubectl get service
kubectl get pod,deployment,replicaset,service
```

- Port-Forward bereitstellen zum lokalen Prüfen

```bash
kubectl port-forward service/sonic 8800:8800
```

### Scaling

#### Option A

- Benutze `scale`-Command

```bash
kubectl scale deployment sonic --replicas=12
```

#### Option B

- Benutze `edit`-Command

```bash
kubectl edit deployment sonic
```

- Setze Feld `spec.replicas` auf `12`
- Speichern

### Publish via Load Balancer

#### Deployment überprüfen

- Prüfe, ob die Pods des Deployment `sonic` laufen

```bash
kubectl get pods -l app=sonic
```

#### Service erstellen

- Service vom Typ `ClusterIP` erstellen, wenn noch nicht vorhanden

```bash
kubectl expose deployment sonic --port=8800 --target-port=8080
```

- Service editieren

```bash
kubectl edit service sonic
```

- Feld `spec.type` auf `LoadBalancer` stellen
- Speichern

#### Services prüfen

- Prüfe den Service

```bash
kubectl get svc
```

- *EXTERNAL-IP* steht auf `<pending>`

    Ouput-Beispiel:
    
    ```bash
    NAME         TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
    kubernetes   ClusterIP      10.0.0.1       <none>        443/TCP          4h42m
    supermario   LoadBalancer   10.0.196.27    <pending>     8800:31400/TCP   107s
    ```

- Warte bis eine IP bereitgestellt wurde

    Output-Beispiel

    ```bash
    NAME         TYPE           CLUSTER-IP     EXTERNAL-IP       PORT(S)          AGE
    kubernetes   ClusterIP      10.0.0.1       <none>            443/TCP          4h42m
    supermario   LoadBalancer   10.0.196.27    134.112.81.190    8800:31400/TCP   2m
    ```

#### Teste den öffentlichen Zugriff

- Öffene einen Browser
- Tippe die IP und den Port `8800` in die Adressleiste ein, bsp. `http://134.112.81.190:8800/`

## Pod mit SQL Zugriff

- SQL Server benötigt: *Allow Azure services and resources to access this server*
- Run SQL Test Image mit Connection String
    - Connection String aus Portal kopieren, Passwort ersetzen
    - Pod erstellen

```bash
kubectl run --image=daniellindemann/sql-test-connection sql-test -- --wait --query 'SELECT @@version' --connectionString '<Connection-String>'
```

## Basic AKS mit SQL Username and Passwort

- Azure Ressourcen durchgehen
- Script Details:
    - AKS Info holen
    - Key Vault Info holen
    - Kubernetes Tools installieren
    - Helm installieren
    - Kubernetes Auth
    - *traefik* Ingress Controller installieren
    - Connection String aus Key Vault auslesen
    - Migrations in Datenbank laden
    - Backend Deployment
        - [`k8s/01-basic-aks/deployment-backend.yaml`](k8s/01-basic-aks/deployment-backend.yaml)
        - Replicas: 3 
        - Connection String wird direkt gesetzt
    - Frontend Deployment
        - [`k8s/01-basic-aks/deployment-frontend.yaml`](k8s/01-basic-aks/deployment-frontend.yaml)
        - Replicas: 3
    - Ingress konfigurieren

```bash
scripts/01-configure-basic-aks.sh $(az group list --query "[?contains(name, 'afstd-scenario1')].name" -o tsv)
```

## Erweiterter AKS mit Datazugriff via Entra ID Auth

- Azure Ressourcen durchgehen
    - Managed Identity
    - SQL Server System-assigned Identity
- Script Details:
    - AKS Info holen
    - Key Vault Info holen
    - Kubernetes Tools installieren
    - Helm installieren
    - Kubernetes Auth
    - *traefik* Ingress Controller installieren
    - Kubernetes Service Account erstellen für Workload Identity
    - Secret Provider Class zum ziehen von Secrets aus Key Vault
    - Busybox Test Pod erstellen für Key Vault Secret retrieval
    - SQL Firewall für aktuellen Client öffnen
    - Grant permissions for managed identity on SQL server
    - Test connection
    - Migrations in Datenbank laden
    - Backend Deployment
        - [`k8s/02-configure-aks-data-access-entra-id/deployment-backend.yaml`](k8s/02-configure-aks-data-access-entra-id/deployment-backend.yaml)
        - Replicas: 3 
        - Connection String wird direkt gesetzt
    - Frontend Deployment
        - [`k8s/02-configure-aks-data-access-entra-id/deployment-frontend.yaml`](k8s/02-configure-aks-data-access-entra-id/deployment-frontend.yaml)
        - Replicas: 3
    - Ingress konfigurieren

```bash
scripts/02-configure-aks-data-access-entra-id.sh $(az group list --query "[?contains(name, 'afstd-scenario2')].name" -o tsv)
```
