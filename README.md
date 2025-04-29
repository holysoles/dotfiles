# dotfiles

## Resources
- https://bash-prompt-generator.org/
- https://github.com/exshak/dotfiles


## New Machine Setup

```bash
#!/bin/bash

set -euo pipefail

GO_VERSION="1.24.2"
NODE_VERSION="22"

case "$(uname -v)" in
    *Ubuntu*)
	DISTRO='ubuntu'
	;;
    *)
	echo "unable to detect distro. Assuming debian."
	DISTRO=''
	;;
esac

if $DISTRO == 'ubuntu'; then
	sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
fi
sudo apt update && sudo apt install -y git make gcc unzip ripgrep xsel fastfetch

# node install for LSPs
wget -O - https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh | bash
\. "$HOME/.nvm/nvm.sh"
nvm install $NODE_VERSION
# install node modules
npm install -g pin-github-action


# golang install
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
rm -rf /usr/local/go
wget -O - "https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz" | sudo tar -C /usr/local -xzf -
echo "PATH=$PATH:/usr/local/go/bin" >> $HOME/.bashrc

# UV Install
wget -qO- https://astral.sh/uv/install.sh | sh
 
# Now setup dotfiles
 
echo "alias dot='/usr/bin/git --git-dir=$HOME/.dotfiles --work-tree=$HOME'" >> $HOME/.bashrc
source $HOME/.bashrc

read -e -p "Should this machine have write access to GitHub? [y/N]" use_ssh

if [ "$use_ssh" = "y" ]; then
    ssh-keygen -q -t ed25519 -C "holysoles97@gmail.com" -N '' -f $HOME/.ssh/id_ed25519 
    echo ""
    echo "--------------------------------------"
    cat ~/.ssh/id_ed25519.pub
    echo "--------------------------------------"
    echo ""
    read -p "Add the above key to GitHub. Press enter when done."
    
    git clone --bare git@github.com:holysoles/dotfiles.git $HOME/.dotfiles
else
    git clone --bare https://github.com/holysoles/dotfiles.git $HOME/.dotfiles
fi

# move conflicts to backup folder
mkdir -p .config-bak && \
dot checkout 2>&1 | egrep "\s+\." | awk {'print $1'} | \
xargs -d $'\n' sh -c 'for arg do mkdir -p (dirname "$arg"); mv "$arg" ".config-bak/${arg}"; done'

# actually checkout the config
dot checkout
dot submodule update --init

# Wrapup
dot config --local status.showUntrackedFiles no
```
