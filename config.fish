# TODO: brew path switch case
# switch (uname)
#   case Darwin
#   case Linux
# end

# https://docs.brew.sh/Shell-Completion
if test -d (brew --prefix)"/share/fish/completions"
    set -gx fish_complete_path $fish_complete_path (brew --prefix)/share/fish/completions
end

if test -d (brew --prefix)"/share/fish/vendor_completions.d"
    set -gx fish_complete_path $fish_complete_path (brew --prefix)/share/fish/vendor_completions.d
end

# tabtab source for pnpm package
# uninstall by removing these lines
[ -f ~/.config/tabtab/fish/__tabtab.fish ]; and . ~/.config/tabtab/fish/__tabtab.fish; or true

fish_add_path (yarn global bin)
export AWS_SDK_LOAD_CONFIG=1
export DOCKER_HOST=unix:///run/user/(id -u)/podman/podman.sock
