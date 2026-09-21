{
  description = "Standalone packages and Hjem configuration for util-scripts (secret-free source root)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    vscode-nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    hjem.url = "github:feel-co/hjem/e5e30b4320a8cbcd6cdfc65f044763669a8f0363";
  };

  outputs = { self, nixpkgs, vscode-nixpkgs, hjem }:
    let
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      importPkgs = system: import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "vscode";
      };
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (importPkgs system));
      defaultUser = "hwangsehyun";
      defaultHomes = {
        aarch64-darwin = "/Users/${defaultUser}";
        x86_64-darwin = "/Users/${defaultUser}";
        aarch64-linux = "/home/${defaultUser}";
        x86_64-linux = "/home/${defaultUser}";
      };

      mkOutputs = system: pkgs:
        let
          lib = pkgs.lib;
          hjemLib = hjem.hjem-lib.${system};
          hjemCli = hjem.packages.${system}.hjem;
          runtimePackages = with pkgs; [
            bash coreutils findutils git hostname rsync gnumake python3
          ];
          runtimePath = lib.makeBinPath runtimePackages;

          restish230 = pkgs.stdenvNoCC.mkDerivation {
            pname = "restish";
            version = "2.3.0";
            src = pkgs.fetchurl {
              url = "https://github.com/rest-sh/restish/releases/download/v2.3.0/restish-2.3.0-${
                if system == "aarch64-darwin" then "darwin-arm64"
                else if system == "aarch64-linux" then "linux-arm64"
                else "linux-amd64"
              }.tar.gz";
              hash = {
                aarch64-darwin = "sha256-XcjVPDGeBE++8BlU+Q6lmxP/G1cOihOCECsMYufnAtI=";
                aarch64-linux = "sha256-1Vrj69Knnm/ajg6hJe7SUw7tYOJ+YeP/okOucq6XPJE=";
                x86_64-linux = "sha256-XeJDU1YFl1Yv/Jl5nqeaDNIsXzyruz/7o/9em5dHM1c=";
              }.${system};
            };
            sourceRoot = ".";
            installPhase = ''
              install -Dm755 restish "$out/bin/restish"
            '';
          };

          mkScript = name: source: pkgs.stdenvNoCC.mkDerivation {
            pname = name;
            version = "1.0.0";
            src = source;
            dontUnpack = true;
            installPhase = ''
              runHook preInstall
              install -Dm755 "$src" "$out/bin/${name}"
              patchShebangs "$out/bin/${name}"
              wrapProgram "$out/bin/${name}" --prefix PATH : ${runtimePath}
              runHook postInstall
            '';
            nativeBuildInputs = [ pkgs.makeWrapper ];
          };

          backupGitWip = mkScript "backup-git-wip.sh" ./assets/scripts/backup-git-wip.sh;

          backupWorkflow = pkgs.stdenvNoCC.mkDerivation {
            pname = "backup-workflow";
            version = "1.0.0";
            dontUnpack = true;
            installPhase = ''
              install -Dm755 ${./assets/scripts/backup-workflow.sh} "$out/bin/backup-workflow.sh"
              install -Dm644 ${./assets/backup.mk} "$out/share/util-scripts/backup.mk"
              substituteInPlace "$out/bin/backup-workflow.sh" \
                --replace-fail 'wip=$script_dir/backup-git-wip.sh' 'wip=${backupGitWip}/bin/backup-git-wip.sh'
              patchShebangs "$out/bin/backup-workflow.sh"
              wrapProgram "$out/bin/backup-workflow.sh" --prefix PATH : ${runtimePath}
            '';
            nativeBuildInputs = [ pkgs.makeWrapper ];
          };

          requestsHttpSignature010 = pkgs.python3Packages.buildPythonPackage rec {
            pname = "requests-http-signature";
            version = "0.1.0";
            format = "setuptools";
            src = pkgs.fetchPypi {
              inherit pname version;
              hash = "sha256-DjnZKEaebxQR47/8p0ooCsk3XU+lvwNVKXTwuk/0w3o=";
            };
            propagatedBuildInputs = [ pkgs.python3Packages.requests ];
            pythonImportsCheck = [ "requests_http_signature" ];
          };

          remoteitSsh = pkgs.python3Packages.buildPythonApplication {
            pname = "remoteit-ssh";
            version = "0.3.1";
            format = "setuptools";
            src = pkgs.fetchFromGitHub {
              owner = "conor-f";
              repo = "remoteit-ssh";
              rev = "5a9e82b018cdc1957c71f3b88e2820bf718d597a";
              hash = "sha256-Q5Eb4M3TmqMtNqg7YVqOxOdrPXQmZLq6HfUN/Bl3HFA=";
            };
            propagatedBuildInputs = [
              pkgs.python3Packages.requests
              requestsHttpSignature010
            ];
            preBuild = ''
              export HOME="$TMPDIR"
            '';
            postInstall = ''
              mv "$out/bin/_remoteit-ssh" "$out/bin/remoteit-ssh"
            '';
            pythonImportsCheck = [ "remoteit_ssh.client" ];
          };

          resilio = pkgs.stdenvNoCC.mkDerivation {
            pname = "resilio-restish";
            version = "1.1.0";
            dontUnpack = true;
            installPhase = ''
              install -Dm755 ${./resilio/resilio-lifecycle} "$out/libexec/resilio-lifecycle"
              install -Dm755 ${./resilio/resilio.10m.py} "$out/share/swiftbar/resilio.10m.py"
              install -Dm755 ${./resilio/resilio-restish-auth.py} "$out/libexec/resilio-restish-auth"
              install -Dm755 ${./resilio/resilio-restish-response.py} "$out/libexec/resilio-restish-response"
              substituteInPlace "$out/libexec/resilio-restish-response" \
                --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3'
              install -Dm644 ${./resilio/openapi.yaml} "$out/share/resilio/openapi.yaml"
              substitute ${./resilio/restish.json} "$out/share/resilio/restish.json" \
                --replace-fail '@RESILIO_OPENAPI@' "$out/share/resilio/openapi.yaml" \
                --replace-fail '@RESILIO_AUTH_HELPER@' "$out/libexec/resilio-restish-auth"
              mkdir -p "$out/bin"
              substitute ${./resilio/resilio-restish} "$out/bin/resilio-restish" \
                --replace-fail '@RESTISH_BIN@' '${restish230}/bin/restish' \
                --replace-fail '@RESTISH_CONFIG@' "$out/share/resilio/restish.json" \
                --replace-fail '@RESILIO_AUTH_HELPER@' "$out/libexec/resilio-restish-auth" \
                --replace-fail '@RESILIO_RESPONSE_CHECKER@' "$out/libexec/resilio-restish-response" \
                --replace-fail '@RESILIO_LIFECYCLE@' "$out/libexec/resilio-lifecycle"
              chmod 755 "$out/bin/resilio-restish" "$out/libexec/resilio-restish-auth" "$out/libexec/resilio-restish-response"
              substituteInPlace "$out/share/swiftbar/resilio.10m.py" \
                --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3' \
                --replace-fail 'CLIENT = pathlib.Path.home() / ".local/bin/resilio-restish"' "CLIENT = pathlib.Path(\"$out/bin/resilio-restish\")"
              patchShebangs "$out/bin/resilio-restish" "$out/libexec/resilio-restish-auth" "$out/libexec/resilio-restish-response"
              wrapProgram "$out/bin/resilio-restish" --prefix PATH : ${lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.jq ]}
              wrapProgram "$out/libexec/resilio-restish-auth" --prefix PATH : ${lib.makeBinPath [ pkgs.lsof ]}
            '';
            nativeBuildInputs = [ pkgs.makeWrapper ];
          };

          vscodePkgs = import vscode-nixpkgs {
            inherit system;
            config.allowUnfreePredicate = pkg: lib.getName pkg == "vscode";
          };
          vscodeVersion = vscodePkgs.vscode.version;
          vscodeCommit = vscodePkgs.vscode.rev;
          vscodeSource = pkgs.fetchFromGitHub {
            owner = "microsoft";
            repo = "vscode";
            rev = vscodeCommit;
            hash = "sha256-79VGSStnb5X32OoSo3NNh62Gbv6JHGtYqgJRP/3+FHA=";
          };
          vscodeAppRoot = if pkgs.stdenv.hostPlatform.isDarwin
            then "${vscodePkgs.vscode}/Applications/Visual Studio Code.app/Contents/Resources/app"
            else "${vscodePkgs.vscode}/lib/vscode/resources/app";

          vscodeCli = vscodePkgs.rustPlatform.buildRustPackage {
            pname = "vscode-cli";
            version = vscodeVersion;
            src = vscodeSource;
            cargoRoot = "cli";
            buildAndTestSubdir = "cli";
            cargoHash = "sha256-qubW1HgtP1NxoBL9SuPo0j4zJjuO7ylaZu8FUqJPEHQ=";
            nativeBuildInputs = [ pkgs.jq pkgs.pkg-config ];
            buildInputs = [ pkgs.openssl pkgs.zlib ];
            VSCODE_CLI_PRODUCT_JSON = "${vscodeAppRoot}/product.json";
            preBuild = ''
              test "$(jq -r .version "${vscodeAppRoot}/package.json")" = "$version"
              test "$(jq -r .commit "${vscodeAppRoot}/product.json")" = "${vscodeCommit}"
              test "$(jq -r .version package.json)" = "$version"
            '';
            nativeCheckInputs = [ pkgs.jq ];
            doCheck = false;
            installPhase = ''
              runHook preInstall
              install -Dm755 target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/release/code "$out/bin/code"
              runHook postInstall
            '';
            postInstall = ''
              cliVersion=$("$out/bin/code" --version)
              printf '%s\n' "$cliVersion"
              printf '%s\n' "$cliVersion" | grep -F "$version"
              printf '%s\n' "$cliVersion" | grep -F "${vscodeCommit}"
              "$out/bin/code" tunnel --help >/dev/null
            '';
            meta = {
              description = "Standalone Visual Studio Code CLI built with Microsoft's product metadata";
              homepage = "https://code.visualstudio.com/";
              license = lib.licenses.mit;
              mainProgram = "code";
              platforms = systems;
            };
          };

          starshipConfig = pkgs.runCommand "starship.toml" {
            nativeBuildInputs = [ pkgs.starship (pkgs.python3.withPackages (p: [ p.toml ])) ];
          } ''
            starship preset no-nerd-font -o no-nerd-font.toml
            starship preset no-runtime-versions -o no-runtime-versions.toml
            python ${./merge-starship.py} no-nerd-font.toml no-runtime-versions.toml ${./assets/shell/starship.toml} "$out"
          '';

          gitConfig = pkgs.runCommand "util-scripts-git-config" {} ''
            sed 's|%s|${pkgs.gh}/bin/gh|g' ${./assets/shell/gitconfig} > "$out"
          '';

          awakeLauncher = pkgs.runCommand "copilot-awake-launcher" {} ''
            sed 's|exec python3|exec ${pkgs.python3}/bin/python3|' \
              ${./swiftbar/copilot-awake.10s.sh} > "$out"
          '';

          homeSources = {
            ".bash_profile" = { source = ./assets/shell/bash_profile.sh; permissions = "0644"; };
            ".config/fish/conf.d/util-scripts.fish" = { source = ./assets/shell/config.fish; permissions = "0644"; };
            ".config/git/ignore" = { source = ./assets/shell/gitignore; permissions = "0644"; };
            ".config/git/config" = { source = gitConfig; permissions = "0644"; };
            ".config/atuin/config.toml" = { source = ./assets/shell/atuin.toml; permissions = "0644"; };
            ".config/starship.toml" = { source = starshipConfig; permissions = "0644"; };
            ".local/bin/code" = { source = "${vscodeCli}/bin/code"; permissions = "0755"; };
            ".local/bin/remoteit-ssh" = { source = "${remoteitSsh}/bin/remoteit-ssh"; permissions = "0755"; };
            ".local/bin/restish" = { source = "${restish230}/bin/restish"; permissions = "0755"; };
            ".local/bin/backup-workflow.sh" = { source = "${backupWorkflow}/bin/backup-workflow.sh"; permissions = "0755"; };
            ".local/bin/backup-git-wip.sh" = { source = "${backupGitWip}/bin/backup-git-wip.sh"; permissions = "0755"; };
            ".config/restish/restish.json" = { source = "${resilio}/share/resilio/restish.json"; permissions = "0600"; };
            ".local/bin/resilio-restish" = { source = "${resilio}/bin/resilio-restish"; permissions = "0755"; };
            ".local/libexec/resilio-restish-auth" = { source = "${resilio}/libexec/resilio-restish-auth"; permissions = "0755"; };
            ".copilot/instructions/byok-subagents.instructions.md" = { source = ./byok/byok-subagents.instructions.md; permissions = "0600"; };
            ".copilot/hooks/byok-subagent-policy.json" = { source = ./byok/byok-subagent-policy.json; permissions = "0600"; };
            ".copilot/local-plugins/byok-subagent-policy/plugin.json" = { source = ./byok/local-plugins/byok-subagent-policy/plugin.json; permissions = "0600"; };
            ".copilot/local-plugins/byok-subagent-policy/com.github.copilot/hooks/hooks.json" = { source = ./byok/local-plugins/byok-subagent-policy/com.github.copilot/hooks/hooks.json; permissions = "0600"; };
            ".copilot/local-plugins/byok-subagent-policy/scripts/byok-subagent-policy.sh" = { source = ./byok/local-plugins/byok-subagent-policy/scripts/byok-subagent-policy.sh; permissions = "0700"; };
            ".copilot/hooks/byok-subagent-policy.sh" = { source = ./byok/local-plugins/byok-subagent-policy/scripts/byok-subagent-policy.sh; permissions = "0700"; };
          } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
            "SwiftBar/copilot-awake.10s.sh" = { source = awakeLauncher; permissions = "0755"; };
            "SwiftBar/copilot-awake/main.py" = { source = ./swiftbar/copilot-awake/main.py; permissions = "0755"; };
            "SwiftBar/resilio.10m.py" = { source = "${resilio}/share/swiftbar/resilio.10m.py"; permissions = "0755"; };
          };

          mkHjemConfiguration = { homeDirectory ? defaultHomes.${system} }:
            let
              evaluated = lib.evalModules {
                specialArgs = { inherit pkgs; hjem-lib = hjemLib; };
                modules = [
                  (hjem + "/modules/common/user.nix")
                  {
                    user = defaultUser;
                    directory = homeDirectory;
                    clobberFiles = false;
                    files = lib.mapAttrs (_: file: file // { type = "copy"; }) homeSources;
                  }
                ];
              };
              config = evaluated.config;
              files = config.files // config.xdg.cache.files // config.xdg.config.files
                // config.xdg.data.files // config.xdg.state.files;
            in {
              manifest = {
                version = 3;
                files = map hjemLib.fileToJson (lib.attrValues (lib.filterAttrs (_: file: file.enable) files));
              };
            };

          hjemConfiguration = mkHjemConfiguration {};
          manifest = pkgs.writeTextFile {
            name = "util-scripts-hjem-manifest.json";
            text = builtins.toJSON hjemConfiguration.manifest;
            checkPhase = ''
              ${lib.getExe hjemCli} manifest validate --manifest "$target"
            '';
          };

          hjemConfig = pkgs.writeText "util-scripts-hjem.nix" ''
            { manifest = builtins.fromJSON (builtins.unsafeDiscardStringContext (builtins.readFile "${manifest}")); }
          '';

          scripts = pkgs.symlinkJoin {
            name = "util-scripts";
            paths = [ backupGitWip backupWorkflow remoteitSsh resilio vscodeCli restish230 ];
          };
        in {
          packages = {
            default = scripts;
            util-scripts = scripts;
            backup-git-wip = backupGitWip;
            backup-workflow = backupWorkflow;
            remoteit-ssh = remoteitSsh;
            resilio = resilio;
            starship-config = starshipConfig;
            vscode-cli = vscodeCli;
            restish = restish230;
            hjem = hjemCli;
            hjem-config = hjemConfig;
            hjem-manifest = manifest;
            inherit (pkgs) awscli2;
          };
          inherit mkHjemConfiguration hjemConfiguration;
        };
    in {
      packages = forAllSystems (pkgs: (mkOutputs pkgs.system pkgs).packages);
      lib.mkHjemConfiguration = system: (mkOutputs system (importPkgs system)).mkHjemConfiguration;
      hjemConfigurations.${defaultUser} = forAllSystems (pkgs: (mkOutputs pkgs.system pkgs).hjemConfiguration);
    };
}
