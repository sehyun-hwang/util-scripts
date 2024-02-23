# util-scripts

> Personal dev env setup using [Makefile](Makefile)

- Used in multiple platforms
  - Cent OS on EC2
  - Mac OS
  - Cent OS on Chrome OS Linux Container
  - Ubuntu on PCs

- Makefile targets
  - `cloud9`
  - `code-tunnel`
  - `awscli`
  - `shell`
  - `scripts`
  - `backup`
  - `swap`

## Usage

### VS Code

1. [Optional] Create [`.vscode/extensions.json`](.vscode/extensions.json) from machine A

    ```sh
    jq '[.[] | .identifier.id] | {"recommendations": . }' -r < ~/.vscode-server/extensions/extensions.json > .vscode/extensions.json
    ```

1. Open this workspace in machine B

    ```sh
    code tunnel      # Recommended for on-premise
    make code-tunnel # Recommended for EC2
    ```

1. Install recommended extensions

## Snippets

### hadolint

```sh
sudo dnf install https://dl.fedoraproject.org/pub/fedora/linux/releases/38/Everything/aarch64/os/Packages/h/hadolint-2.12.0-10.fc38.aarch64.rpm
```

### brew

```sh
ln -s /home/linuxbrew/.linuxbrew/Cellar/libffi/*/lib64/libffi.so.8 /home/linuxbrew/.linuxbrew/lib/libffi.so.8

brew deps hadolint --include-build --missing | grep -v -E 'cmake|gcc|llvm|rust|ninja|swig|pkg-config|go' | xargs brew install --ignore-dependencies
brew install ruff --ignore-dependencies

rm /home/linuxbrew/.linuxbrew/Homebrew/Library/Homebrew/shims/linux/super/gcc
```
