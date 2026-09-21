{
  description = "Standalone packages and Hjem configuration for util-scripts";

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

          goPkgs = import vscode-nixpkgs {
            inherit system;
            config.allowUnfree = false;
          };

          restish230 = goPkgs.buildGoModule {
            pname = "restish";
            version = "2.3.0";
            src = pkgs.fetchFromGitHub {
              owner = "rest-sh";
              repo = "restish";
              rev = "6305246a75121a7373563577e50e9bf522baca6b";
              hash = "sha256-tI4o+zkKNnFrqWFEHsNt2+03Luth9KHH+x7P+WwaGNI=";
            };
            vendorHash = "sha256-Y0GwgrkD09WAlmyI6Oe3Kw6L62E7QRTCIThZGXbbn74=";
            subPackages = [ "cmd/restish" ];
            ldflags = [
              "-s"
              "-w"
              "-X github.com/rest-sh/restish/v2/internal/cli.Version=2.3.0"
            ];
            meta = {
              description = "CLI for interacting with REST APIs";
              homepage = "https://rest.sh/";
              license = lib.licenses.mit;
              mainProgram = "restish";
            };
          };

          toolhivePatched = goPkgs.buildGoModule {
            pname = "thv-patched";
            version = "0.46.0";
            src = pkgs.fetchFromGitHub {
              owner = "stacklok";
              repo = "toolhive";
              rev = "c6c425a924fac51c86cbade15d0e720e29a600ab";
              hash = "sha256-U5WJmnVEYeE0DHNIln+N9OC6dLJzwaeF8OunhgsdmiM=";
            };
            patches = [ ./patches/toolhive-explicit-oauth.patch ];
            vendorHash = "sha256-sg2W+cWmaCguL/pCH8+RrROJUDp23qHn24HeARvXhyU=";
            subPackages = [ "cmd/thv" ];
            ldflags = [
              "-s"
              "-w"
              "-X github.com/stacklok/toolhive/pkg/versions.Version=v0.46.0-patched"
              "-X github.com/stacklok/toolhive/pkg/versions.Commit=c6c425a924fac51c86cbade15d0e720e29a600ab"
              "-X github.com/stacklok/toolhive/pkg/versions.BuildType=development"
            ];
            postInstall = ''
              mv "$out/bin/thv" "$out/bin/thv-patched-unwrapped"
              makeWrapper "$out/bin/thv-patched-unwrapped" "$out/bin/thv-patched" \
                --set-default TOOLHIVE_SKIP_DESKTOP_CHECK 1
            '';
            nativeBuildInputs = [ pkgs.makeWrapper ];
            meta = {
              description = "ToolHive CLI patched to prefer explicit OAuth configuration";
              homepage = "https://github.com/stacklok/toolhive";
              license = lib.licenses.asl20;
              mainProgram = "thv-patched";
            };
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

          backupGitWip = mkScript "backup-git-wip.sh" ./backup-workflow/backup-git-wip.sh;

          backupWorkflow = pkgs.stdenvNoCC.mkDerivation {
            pname = "backup-workflow";
            version = "1.0.0";
            dontUnpack = true;
            installPhase = ''
              install -Dm755 ${./backup-workflow/backup-workflow.sh} "$out/bin/backup-workflow.sh"
              install -Dm644 ${./backup-workflow/backup.mk} "$out/share/util-scripts/backup.mk"
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
              ${pkgs.python3}/bin/python3 - ${./resilio/restish.json} "$out/share/resilio/restish.json" \
                "$out/share/resilio/openapi.yaml" "$out/libexec/resilio-restish-auth" <<'PY'
              import json, sys
              source, target, schema, helper = sys.argv[1:]
              with open(source, encoding="utf-8") as stream:
                  config = json.load(stream)
              api = config["apis"]["resilio"]
              api["spec_files"] = [schema]
              api["profiles"]["default"]["auth"]["params"]["commandline"] = helper
              with open(target, "w", encoding="utf-8") as stream:
                  json.dump(config, stream, indent=2)
                  stream.write("\n")
              PY
              install -Dm755 ${./resilio/resilio-restish} "$out/bin/resilio-restish"
              chmod 755 "$out/bin/resilio-restish" "$out/libexec/resilio-restish-auth" "$out/libexec/resilio-restish-response"
              substituteInPlace "$out/share/swiftbar/resilio.10m.py" \
                --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3' \
                --replace-fail 'CLIENT = pathlib.Path.home() / ".local/bin/resilio-restish"' "CLIENT = pathlib.Path(\"$out/bin/resilio-restish\")"
              patchShebangs "$out/bin/resilio-restish" "$out/libexec/resilio-restish-auth" "$out/libexec/resilio-restish-response"
              wrapProgram "$out/bin/resilio-restish" \
                --prefix PATH : ${lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.jq ]} \
                --set-default RESTISH_BIN '${restish230}/bin/restish' \
                --set-default RESILIO_RESTISH_AUTH_HELPER "$out/libexec/resilio-restish-auth" \
                --set-default RESILIO_RESTISH_RESPONSE_CHECKER "$out/libexec/resilio-restish-response" \
                --set-default RESILIO_RESTISH_LIFECYCLE "$out/libexec/resilio-lifecycle"
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
            python ${./shell/merge-starship.py} no-nerd-font.toml no-runtime-versions.toml ${./shell/starship.toml} "$out"
          '';

          gitConfig = pkgs.runCommand "util-scripts-git-config" {} ''
            sed 's|%s|${pkgs.gh}/bin/gh|g' ${./shell/gitconfig} > "$out"
          '';

          awakeLauncher = pkgs.runCommand "copilot-awake-launcher" {} ''
            sed 's|exec python3|exec ${pkgs.python3}/bin/python3|' \
              ${./swiftbar/copilot-awake.10s.sh} > "$out"
          '';

          awsCostPlugin = pkgs.runCommand "awsmonthcost.1h.sh" {
            nativeBuildInputs = [ pkgs.makeWrapper ];
          } ''
            install -Dm755 ${./swiftbar/awsmonthcost.1h.sh} "$out"
            wrapProgram "$out" \
              --set-default AWS_BIN '${pkgs.awscli2}/bin/aws' \
              --set-default JQ_BIN '${pkgs.jq}/bin/jq'
          '';

          timeMachinePlugin = pkgs.runCommand "timemachine.1m.sh" {} ''
            cp ${./swiftbar/timemachine.1m.sh} "$out"
            chmod 755 "$out"
          '';

          homeSources = {
            ".bash_profile" = { source = ./shell/bash_profile.sh; permissions = "0644"; };
            ".config/fish/conf.d/util-scripts.fish" = { source = ./shell/config.fish; permissions = "0644"; };
            ".config/git/ignore" = { source = ./shell/gitignore; permissions = "0644"; };
            ".config/git/config" = { source = gitConfig; permissions = "0644"; };
            ".config/atuin/config.toml" = { source = ./shell/atuin.toml; permissions = "0644"; };
            ".config/starship.toml" = { source = starshipConfig; permissions = "0644"; };
            ".local/bin/code" = { source = "${vscodeCli}/bin/code"; permissions = "0755"; };
            ".local/bin/remoteit-ssh" = { source = "${remoteitSsh}/bin/remoteit-ssh"; permissions = "0755"; };
            ".local/bin/restish" = { source = "${restish230}/bin/restish"; permissions = "0755"; };
            ".local/bin/thv-patched" = { source = "${toolhivePatched}/bin/thv-patched"; permissions = "0755"; };
            ".local/bin/backup-workflow.sh" = { source = "${backupWorkflow}/bin/backup-workflow.sh"; permissions = "0755"; };
            ".local/bin/backup-git-wip.sh" = { source = "${backupGitWip}/bin/backup-git-wip.sh"; permissions = "0755"; };
            ".config/restish/restish.json" = { source = "${resilio}/share/resilio/restish.json"; permissions = "0600"; };
            ".local/bin/resilio-restish" = { source = "${resilio}/bin/resilio-restish"; permissions = "0755"; };
            ".local/libexec/resilio-restish-auth" = { source = "${resilio}/libexec/resilio-restish-auth"; permissions = "0755"; };
            ".copilot/instructions/byok-subagents.instructions.md" = { source = ./copilot/byok-subagents.instructions.md; permissions = "0600"; };
            ".copilot/hooks/byok-subagent-policy.json" = { source = ./copilot/byok-subagent-policy.json; permissions = "0600"; };
            ".copilot/local-plugins/byok-subagent-policy/plugin.json" = { source = ./copilot/local-plugins/byok-subagent-policy/plugin.json; permissions = "0600"; };
            ".copilot/local-plugins/byok-subagent-policy/com.github.copilot/hooks/hooks.json" = { source = ./copilot/local-plugins/byok-subagent-policy/com.github.copilot/hooks/hooks.json; permissions = "0600"; };
            ".copilot/local-plugins/byok-subagent-policy/scripts/byok-subagent-policy.sh" = { source = ./copilot/local-plugins/byok-subagent-policy/scripts/byok-subagent-policy.sh; permissions = "0700"; };
            ".copilot/hooks/byok-subagent-policy.sh" = { source = ./copilot/local-plugins/byok-subagent-policy/scripts/byok-subagent-policy.sh; permissions = "0700"; };
          } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
            "SwiftBar/awsmonthcost.1h.sh" = { source = awsCostPlugin; permissions = "0755"; };
            "SwiftBar/copilot-awake.10s.sh" = { source = awakeLauncher; permissions = "0755"; };
            "SwiftBar/copilot-awake/main.py" = { source = ./swiftbar/copilot-awake/main.py; permissions = "0755"; };
            "SwiftBar/resilio.10m.py" = { source = "${resilio}/share/swiftbar/resilio.10m.py"; permissions = "0755"; };
            "SwiftBar/timemachine.1m.sh" = { source = timeMachinePlugin; permissions = "0755"; };
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

        in {
          packages = {
            backup-git-wip = backupGitWip;
            backup-workflow = backupWorkflow;
            remoteit-ssh = remoteitSsh;
            resilio = resilio;
            starship-config = starshipConfig;
            vscode-cli = vscodeCli;
            restish = restish230;
            thv-patched = toolhivePatched;
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
