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

atuin init fish | .
if test (uname) = Darwin
    export ATUIN_SYNC_ADDRESS=http://atuin.orb.local:8888
else
    export ATUIN_SYNC_ADDRESS=(docker ps -f name=atuin --format '{{.Ports}}' | sed -n 's=.*:\([0-9]*\)->.*=http://localhost:\1=p')
end

if not test -w (realpath /var/run/docker.sock)
    export DOCKER_HOST=unix:///run/user/(id -u)/podman/podman.sock
end

fish_add_path ~/.local/bin (yarn global bin)
export AWS_SDK_LOAD_CONFIG=1
