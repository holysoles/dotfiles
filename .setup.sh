#!/bin/bash

set -euo pipefail

GO_VERSION="1.24.2"
NODE_VERSION="22"

release_id=$(lsb_release --id | sed 's/Distributor ID\:\t//')
case "$release_id" in
    *Ubuntu*)
        DISTRO='ubuntu'
        ;;
    *)
        echo "unable to detect distro. Assuming debian."
        DISTRO=''
        ;;
esac

# check if WSL
if [ -n "$(uname -r | grep WSL)" ]; then
    printf "\n\nsystem is WSL, configuring system..\n"
    wsl_conf=$(cat <<-EOT
    [boot]
    systemd=true
    [interop]
    appendWindowsPath = false
    [network]
    generateResolvConf = false
EOT
)
    echo "$wsl_conf" | sudo tee /etc/wsl.conf > /dev/null

    if [ -z "$(lsattr /etc/resolv.conf | grep i)" ]; then
        # generateResolvConf = false doesnt always work, use a workaround:
        resolv_conf=$(cat "/etc/resolv.conf")
        sudo rm /etc/resolv.conf
        echo "$resolv_conf" | sudo tee /etc/resolv.conf > /dev/null
        sudo chattr +i /etc/resolv.conf
        printf "/etc/resolv.conf set to immutable to fix bug, update as needed\n"
    fi
fi


printf "\n\ninstalling packages..\n"
if [ "$DISTRO" = 'ubuntu' ]; then
        sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch > /dev/null
fi
sudo apt update -qq
sudo apt install -y -qq git make gcc unzip ripgrep xsel fastfetch

# node install for LSPs
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh | bash > /dev/null
\. "$HOME/.nvm/nvm.sh"
printf "\n\ninstalling node v${NODE_VERSION} with nvm..\n"
nvm install $NODE_VERSION
if [ "$DISTRO" == "ubuntu" ]; then
	# use system certificates in case we're on a network with a proxy
	npm config set cafile /etc/ssl/certs/ca-certificates.crt
fi
# install node modules
npm install -g pin-github-action


# golang install
if [ -z "$(/usr/local/go/bin/go version) || true | grep $GO_VERSION)" ]; then
    printf "\n\ninstalling Go..\n"
    GOARCH=""
    arch=$(arch)
    case $arch in
        x86_64)
            GOARCH="amd64"
            ;;
        *)
            echo "error, could not detect arch for go install"
            exit 1
    esac
    sudo rm -rf /usr/local/go
    wget -qO- "https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz" | sudo tar -C /usr/local -xzf -
fi

# UV Install
printf "\n\ninstalling uv..\n"
wget -qO- https://astral.sh/uv/install.sh | sh > /dev/null

# Now setup dotfiles
function dot {
   /usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME $@
}

printf "\n\n"
read -e -p "Should this machine have write access to GitHub? [y/N]" use_ssh

dotfiles="$HOME/.dotfiles"
if [ ! -d $dotfiles ]; then
    if [ "$use_ssh" = "y" ]; then
        ssh-keygen -q -t ed25519 -C "holysoles97@gmail.com" -N '' -f $HOME/.ssh/id_ed25519
        echo ""
        echo "--------------------------------------"
        cat ~/.ssh/id_ed25519.pub
        echo "--------------------------------------"
        echo ""
        read -p "Add the above key to GitHub. Press enter when done."

        git clone --bare git@github.com:holysoles/dotfiles.git "$dotfiles"
    else
        git clone --bare https://github.com/holysoles/dotfiles.git "$dotfiles"
    fi

    # move conflicts to backup folder
    mkdir -p .config-bak
    checkout=$(/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME checkout 2>&1 || true)
    diff=$(echo "$checkout" | egrep "\s+\.|README.md" | awk {'print $1'})
    dir_names=$(echo "$diff" | xargs -I{} dirname {})
    echo "$dir_names" | xargs -I{} mkdir -p .config-bak/{}
    echo "$diff" | xargs -I{} mv {} .config-bak/{}

    # actually checkout the config
    dot checkout

    dot submodule update --init
else
    dot pull
    dot submodule update
fi

# Wrapup
eval dot config --local status.showUntrackedFiles no

printf "\n\nsetup complete!\n"
