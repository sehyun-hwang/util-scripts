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

export AWS_SDK_LOAD_CONFIG=1
export DOCKER_HOST=unix:///run/user/(id -u)/podman/podman.sock
