unset LANG

export PIP_INDEX_URL=http://localhost:3141/simple/
export PIP_TRUSTED_HOST=localhost

alias fish=/opt/homebrew/bin/fish

init() {
    cd /Volumes/dev
    /opt/homebrew/bin/fish
}
