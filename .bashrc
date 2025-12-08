# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# CONTROL FLOW VARS
if command -v kubectl > /dev/null; then
    export KUBE_INSTALLED="true"
fi


# SHELL OPTIONS
# don't put duplicate lines or lines starting with space in the history.
HISTCONTROL=ignoreboth
# append to the history file, don't overwrite it
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000
# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize
# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
shopt -s globstar
# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"


# PROMPT
# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi
# color detection
if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    # We have color support; assume it's compliant with Ecma-48
    # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
    # a case would tend to support setf rather than setaf.)
    color_prompt=yes
else
    color_prompt=
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt
NORMAL="\[\033[00m\]"
BLUE="\[\033[01;34m\]"
YELLOW="\[\e[1;33m\]"
GREEN="\[\e[1;32m\]"


if [ -n "$KUBE_INSTALLED" ]; then
    . ~/.kube-prompt.sh
fi
. ~/.git-prompt.sh
GIT_PS1_SHOWCONFLICTSTATE="true"
GIT_PS1_SHOWCOLORHINTS="true"
GIT_PS1_SHOWDIRTYSTATE="true"
GIT_PS1_SHOWUNTRACKEDFILES="true"
GIT_PS1_SHOWUPSTREAM="true"
PROMPT_COMMAND='KUBE_STATUS=$(__kube_ps1); GIT_STATUS=$(__git_ps1 "(%s)")'
PS1='${KUBE_STATUS}${GIT_STATUS} \[\e[94m\]\W\[\e[0m\]> '


# ENV
if [ -f ~/.local/bin/env ]; then
    . ~/.local/bin/env
fi
if [ -f ~/.bash_env ]; then
    . ~/.bash_env
fi
export NVM_DIR="$HOME/.nvm"
export PATH="$PATH:/usr/local/go/bin"
export PATH="$PATH:$(go env GOPATH)/bin"
if [ -d /home/patrick/.platformio/penv/bin ]; then
    export PATH="$PATH:$HOME/.platformio/penv/bin/"
fi
if command -v nvim > /dev/null; then
    export EDITOR=nvim
else
    export EDITOR=vi
fi

# ALIASES
#if [ -f ~/.bash_aliases ]; then
#    . ~/.bash_aliases
#fi
# alias basic commands to have color
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
    alias rgrep='rgrep --color=auto'
fi
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias n='nvim'
alias vim='nvim'
alias dot='/usr/bin/git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
alias gpf='git push --force-with-lease'
# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
alias co='cd ~/code/'
alias rco='cd ~/remote-code/'
alias nx='cd ~/Nextcloud/'
alias k='kubectl'
alias ksw='kubectl config use-context'
alias watchh='watch '
alias flushdns='sudo resolvectl flush-caches'
alias cat='batcat'
CLIP=xsel
PASTE=xsel
if [ "$XDG_SESSION_TYPE" = 'wayland' ]; then
	CLIP=wl-copy
	PASTE=wl-paste
fi
alias clip=$CLIP
alias paste=$PASTE
# functions
function flux-retry-helm() {
  local NAMESPACE="$1"
  local HELMRELEASE="$2"

  TOKEN="$(date +%s)"
  kubectl annotate helmrelease --field-manager=flux-client-side-apply --overwrite -n "$NAMESPACE" "$HELMRELEASE" \
    "reconcile.fluxcd.io/requestedAt=$TOKEN" "reconcile.fluxcd.io/forceAt=$TOKEN"
}

# TAB COMPLETIONS
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
if [ -n "$KUBE_INSTALLED" ]; then
    . <(kubectl completion bash)
    complete -o default -F __start_kubectl k
    if command -v flux > /dev/null; then
        . <(flux completion bash)
    fi
fi
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion


# CMDS
if [ -n "$(which fastfetch)" ]; then
    # TODO filter on asahi (kernel name?)
    #sleep 0.1 # sleep since fastfetch fails to retrieve screen size initially on asahi
    fastfetch
fi

