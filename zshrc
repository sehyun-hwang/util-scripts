unset LANG

export PIP_INDEX_URL=http://localhost:3141/simple/
export PIP_TRUSTED_HOST=localhost

alias fish=$HOME/.nix-profile/bin/fish

init() {
    cd /Volumes/dev-internal
    exec $HOME/.nix-profile/bin/fish
}
