export AWS_SDK_LOAD_CONFIG=1
export PODMAN_IGNORE_CGROUPSV1_WARNING=1

set YARN_EXECUTABLE yarn
if test -x /tmp
    set YARN_EXECUTABLE ~/.nix-profile/bin/yarn
end
fish_add_path ~/.local/bin ($YARN_EXECUTABLE global bin)

set BREW_EXECUTABLE (ls /home/linuxbrew/.linuxbrew/bin/brew /opt/homebrew/bin/brew 2> /dev/null)

if [ "$BREW_EXECUTABLE" ]
    eval ($BREW_EXECUTABLE shellenv)

    # https://docs.brew.sh/Shell-Completion
    if test -d (brew --prefix)"/share/fish/completions"
        set -gx fish_complete_path $fish_complete_path (brew --prefix)/share/fish/completions
    end

    if test -d (brew --prefix)"/share/fish/vendor_completions.d"
        set -gx fish_complete_path $fish_complete_path (brew --prefix)/share/fish/vendor_completions.d
    end
end

# https://github.com/aws/aws-cli/issues/1079#issuecomment-541997810
complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed \'s/ $//\'; end)'

# pnpm
set -gx PNPM_HOME ~/.local/share/pnpm
if not string match -q -- $PNPM_HOME $PATH
    set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end

command -q starship; and starship init fish | source

if test (uname) = Darwin
    export ATUIN_SYNC_ADDRESS=http://atuin.orb.local:8888
else
    set DOCKER_PS_ATUIN_PORT (docker ps -f name=atuin --format '{{.Ports}}')
    if test -z $DOCKER_PS_ATUIN_PORT
        echo Atuin sync server is not running
    else
        export ATUIN_SYNC_ADDRESS=(echo $DOCKER_PS_ATUIN_PORT | sed -n 's=.*:\([0-9]*\)->.*=http://localhost:\1=p')
    end
end
command -q atuin; and atuin init fish | .

set PODMAN_SOCKET (docker info -f '{{.Host.RemoteSocket.Path}}')
if test -n $PODMAN_SOCKET
    export DOCKER_HOST=unix://$PODMAN_SOCKET
end
