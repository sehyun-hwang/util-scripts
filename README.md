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

### Copilot BYOK subagent policy (macOS)

```bash
make byok-install
```

The [Makefile](Makefile) copies static policy files from [byok/](byok/) using
`cp` and installs the executable hook with `install -m 700`. No installer helper,
backups, or automatic VS Code settings changes are used. Runtime requires Bash,
`jq`, a VS Code build supporting Agent Plugins, and `chatgpt/gpt-5.6-sol`
registered in each channel you use. The hook finds `jq` on PATH or in standard
Homebrew/system locations. Installation includes the global instruction,
standalone hook, and an Agent Plugins 1.0 package at
`~/.copilot/local-plugins/byok-subagent-policy`. Its `PreToolUse` hook requires
this exact model for `task`, `Task`, `functions.task`, and VS Code's runtime
`Agent` alias:

`customendpoint/cliproxyapi customendpoint/chatgpt/gpt-5.6-sol`

The parent chat model is unrestricted. **Register the plugin manually** in both
Stable and Insiders user settings, merging this entry into any existing
`chat.pluginLocations` object (replace `/Users/YOUR_USER` with your home path):

```jsonc
"chat.pluginLocations": {
  "/Users/YOUR_USER/.copilot/local-plugins/byok-subagent-policy": true
}
```

Ensure `chat.plugins.enabled` is not disabled. Installation does not modify
Settings Sync, guidance settings, Agent Host configuration, or either channel's
settings. Managed policy files are overwritten without backups on reinstall;
non-executable files have mode 600 and executable scripts have mode 700.

Both hook configurations invoke `/bin/bash` with a quoted `$HOME` path. One
canonical script is installed to both hook destinations. It accepts SDK
`toolName`/`toolArgs`, batched `toolCalls`, and command-hook
`tool_name`/`tool_input` payloads, emitting both SDK and VS Code decisions.
The standalone compatibility hook and plugin hook may both run. Remove any
existing standalone `.disabled` marker manually if that hook should be active.

Run the existing policy self-tests with:

```bash
make byok-test
```

Reload Stable and Insiders after installation, verify discovery in
**Chat: Open Customizations**, and verify enforcement in fresh sessions.
The plugin requests a five-second hook timeout. Error, timeout, and multiple-hook
handling depend on the active Agent Host runtime; local tests do not prove
provider reachability or live pre-provider enforcement. Do not treat this
plugin as a tamper-proof machine security boundary.

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
