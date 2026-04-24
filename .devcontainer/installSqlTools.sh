#!/bin/bash

DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
DISTRO_VERSION=$(lsb_release -rs)

apt-get update && apt-get install software-properties-common -y

# see https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-download-install?view=sql-server-ver17&tabs=linux
# there is no 24.04
curl https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc
add-apt-repository -y "$(wget -qO- https://packages.microsoft.com/config/ubuntu/22.04/prod.list)"
apt-get update && apt-get install sqlcmd -y
