# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
        . ~/.bashrc
fi

# User specific environment and startup programs
export PATH=/mnt/utils:$PATH:~/go/bin
eval $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)
# pnpm
export PNPM_HOME="/home/centos/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

export AWS_SDK_LOAD_CONFIG=1
export DOCKER_HOST=unix:///run/user/1000/podman/podman.sock
#export DOCKER_BUILDKIT=0
export ESLINT_USE_FLAT_CONFIG=true

[ -z "$C9_HOSTNAME" ] || exec fish
