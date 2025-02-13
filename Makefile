#############
# Constants #
#############

ifndef HOME
$(error $$HOME is not set)
endif
ifndef USER
$(error $$USER is not set)
endif

BLOB_DIR := /volatile
ifeq ($(wildcard ${BLOB_DIR}),)
BLOB_DIR := ${HOME}/volatile
endif
$(info BLOB_DIR ${BLOB_DIR})

###########
# VS Code #
###########

ifeq ($(shell uname),Linux)
VSCODE_OS := alpine
else
VSCODE_OS := darwin
endif
ifeq ($(shell arch),x86_64)
VSCODE_ARCH := x64
else
VSCODE_ARCH := arm64
endif

${HOME}/.local/bin/code:
	# https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64
	# https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-arm64
	# https://code.visualstudio.com/sha/download?build=stable&os=cli-darwin-arm64
	curl -fL 'https://code.visualstudio.com/sha/download?build=stable&os=cli-${VSCODE_OS}-${VSCODE_ARCH}' \
	| tar -xvzC $(dir $@) -f-
	chmod +x $@
	code --version

code-symlink:
	mkdir -p ${BLOB_DIR}/vscode-server
	ln -s ${BLOB_DIR}/vscode-server ~/.vscode-server

.PHONY: code-tunnel
code-tunnel: ${HOME}/.local/bin/code | ${BLOB_DIR}/swap
	systemd-run -p MemoryMax=2.5G -p MemorySwapMax=2G --user --scope code tunnel

###########
# AWS CLI #
###########

AWSCLI_DIR := .
AWSCLI_WHEEL := $(firstword $(wildcard ${AWSCLI_DIR}/awscli-*-py3-none-any.whl))
ifeq (${AWSCLI_WHEEL},)
AWSCLI_WHEEL := ${AWSCLI_DIR}/awscli-$(shell curl -fs 'https://api.github.com/repos/aws/aws-cli/tags?per_page=1' | jq -r .[0].name)-py3-none-any.whl
endif
AWSCLI_VENV := $(shell pipx environment --value PIPX_LOCAL_VENVS)/awscli

${AWSCLI_WHEEL}:
	pip wheel https://github.com/aws/aws-cli/archive/v2.zip --no-deps
${HOME}/.local/bin/aws: ${AWSCLI_WHEEL}
	pipx install $< || pipx install --python $$(which python) $<
	$@ --version

${AWSCLI_VENV}/lib/%/site-packages/awscli/data/ac.index: ${HOME}/.local/bin/aws
	cd ${AWSCLI_VENV}/lib/*/site-packages \
	&& VERSION=$$(python -c 'import awscli; print(awscli.__version__)') \
	&& echo $$VERSION \
	&& NAME=$$(docker create docker.io/amazon/aws-cli:$$VERSION) \
	&& docker cp $$NAME:/usr/local/aws-cli/v2/$$VERSION/dist/awscli/data/ac.index $@ \
	&& docker rm $$NAME

.PHONY: awscli
awscli: ${HOME}/.local/bin/aws
	$(MAKE) $$(pipx runpip awscli show awscli | awk '/^Location:/ {print $$2}')/awscli/data/ac.index

#######################
# Shell Configuration #
#######################

.PHONY: shell
shell: $(addprefix ${HOME}/,.local/bin/atuin .bash_profile .zshrc .config/fish/conf.d/make.fish .config/git/ignore .config/git/config .ssh/id_ed25519)

$(addprefix ${HOME}/.local/bin,.config/fish/conf.d .config/git .ssh):
	mkdir -p $@

${HOME}/.local/bin/atuin: | ${HOME}/.local/bin
	curl https://github.com/atuinsh/atuin/releases/latest/download/atuin-installer.sh -L \
		| CARGO_DIST_FORCE_INSTALL_DIR=$| ATUIN_NO_MODIFY_PATH=1 sh -s --

${HOME}/.bash_profile: bash_profile.sh
	cp $< $@
${HOME}/.zshrc: zshrc
	cp $< $@
${HOME}/.config/fish/conf.d/make.fish: config.fish | ${HOME}/.config/fish/conf.d
	cp $< $@

${HOME}/.config/git/ignore: gitignore | ${HOME}/.config/git
	cp $< $@
${HOME}/.config/git/config: gitconfig | ${HOME}/.config/git
	cp $< $@

${HOME}/.ssh/id_ed25519: id_ed25519 | ${HOME}/.ssh
	chmod 600 $<
	ssh-keygen -pf $< -N ''
	chmod 400 $<
	mv $< $@
	git checkout HEAD -- $<

###########
# Scripts #
###########

SCRIPT_FILES := backup.sh ecr.sh lambda.sh resize.sh secret.fish ec2.py ssh-mac.py
# https://www.gnu.org/software/make/manual/html_node/Text-Functions.html
SCRIPT_FILES := $(SCRIPT_FILES:%=${HOME}/.local/bin/%)
$(info SCRIPT_FILES ${SCRIPT_FILES})

.PHONY: scripts
scripts: $(SCRIPT_FILES)

# Shell scripts
${HOME}/.local/bin/resize.sh:
	wget -O $@ https://raw.githubusercontent.com/EugenMayer/parted-auto-resize/master/resize.sh
	chmod +x $@
${HOME}/.local/bin/%.sh: %.sh
	cp $< $@
${HOME}/.local/bin/%.fish: %.fish
	cp $< $@

# Python scripts
PYTHON_VENV := ${BLOB_DIR}/venv/python$(shell python -c 'import sysconfig; print(sysconfig.get_python_version())')
PYTHON_SITE_DIR := $(shell python -c 'import venv; print(venv.EnvBuilder()._venv_path("${PYTHON_VENV}", "purelib"))')
EC2_SSH_REQUIREMENTS := $(addprefix ${PYTHON_SITE_DIR}/,boto3 paramiko paramiko_tunnel requests simple_term_menu.py)
$(info PYTHON_VENV ${PYTHON_VENV})
$(info PYTHON_SITE_DIR ${PYTHON_SITE_DIR})

${PYTHON_VENV}:
	python -m venv $@
${PYTHON_SITE_DIR}: | ${PYTHON_VENV}
${PYTHON_SITE_DIR}/requests_http_signature: | ${PYTHON_SITE_DIR}
	# https://github.com/conor-f/remoteit-ssh/blob/main/requirements.txt
	${PYTHON_VENV}/bin/pip install requests_http_signature==v0.1.0
${EC2_SSH_REQUIREMENTS}: | ${PYTHON_SITE_DIR}/requests_http_signature
	${PYTHON_VENV}/bin/pip install $(subst _,-,$(basename $(notdir ${EC2_SSH_REQUIREMENTS})))
${PYTHON_SITE_DIR}/interactive_shell.py: interactive_shell.py | ${PYTHON_SITE_DIR}
	cp $< $@
${PYTHON_SITE_DIR}/remoteit_ssh_client.py: remoteit_ssh_client.sed | ${PYTHON_SITE_DIR}
	curl https://raw.githubusercontent.com/conor-f/remoteit-ssh/main/src/remoteit_ssh/client.py \
		| sed -f $< \
		> $@

${HOME}/.local/bin/%.py: %.py ${PYTHON_SITE_DIR}/interactive_shell.py ${PYTHON_SITE_DIR}/remoteit_ssh_client.py | ${EC2_SSH_REQUIREMENTS}
	echo '#!${PYTHON_VENV}/bin/python' > $@
	cat $< >> $@
	chmod +x $@

##########
# Backup #
##########

$(shell	mkdir -p backup)

.PHONY: backup
backup: backup/ssh-config.txt backup/fish.json backup/vscode.json
	which dnf && dnf history > backup/dnf.txt
	which apt && apt-mark showmanual > backup/apt.txt
	which brew && brew leaves > backup/brew.txt
	which pnpm && pnpm ls -g > backup/pnpm.txt
	which yarn && yarn global list > backup/yarn.txt

backup/ssh-config.txt: ${HOME}/.ssh/config
	cp $< $@
backup/fish.json: ${HOME}/.local/share/fish/fish_history
	cp $< $@
backup/vscode.json: ~/.vscode-server/data/Machine/settings.json
	cp $< $@
