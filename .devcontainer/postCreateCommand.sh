#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
# Treat unset variables as an error and exit
# Return the exit status of the last command in a pipeline that failed
set -euo pipefail

script_dir=$(dirname "$0")

# ensure temp directory exists
ensure_temp_dir() {
    if [ ! -d "$script_dir/.temp" ]; then
        mkdir -p "$script_dir/.temp"
    fi
}

# ensure permissions in home directory
sudo chown -R "$(whoami)" "$HOME"

# install tools
IS_ARM=$(if [[ $(uname -m) == 'aarch64' || $(uname -m) == "arm64" ]]; then echo true; else echo false; fi)
# install k9s
if ! command -v k9s &> /dev/null; then
    echo "Installing k9s"
    ensure_temp_dir

    k9s_VERSION_DOWNLOAD_FILE_SUFFIX=$(if [[ $IS_ARM = true ]]; then echo 'Linux_arm64'; else echo 'Linux_amd64'; fi)
    k9s_VERSION=$(
        curl --silent "https://api.github.com/repos/derailed/k9s/releases/latest" | \
            grep '"tag_name":' | \
            sed -E 's/.*"v([^"]+)".*/\1/' \
    )

    # check if file k9s-${k9s_VERSION}.tar.gz already exists in .temp directory
    if [ ! -f "$script_dir/.temp/k9s-${k9s_VERSION}.tar.gz" ]; then
        curl -L -o "$script_dir/.temp/k9s-${k9s_VERSION}.tar.gz" "https://github.com/derailed/k9s/releases/download/v${k9s_VERSION}/k9s_${k9s_VERSION_DOWNLOAD_FILE_SUFFIX}.tar.gz"
    fi

    # extract and move to /usr/local/bin
    tar -xvzf "$script_dir/.temp/k9s-${k9s_VERSION}.tar.gz" -C "$script_dir/.temp/" k9s && sudo mv "$script_dir/.temp/k9s" /usr/local/bin
    echo "k9s installed"
fi

echo "✅ Post-create command completed successfully."
