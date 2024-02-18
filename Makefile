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
# Cloud 9 #
###########

.PHONY: cloud9
cloud9: ${HOME}/.c9/python3/bin/pylint

${HOME}/.c9:
	curl https://d3kgj69l4ph6w4.cloudfront.net/static/c9-install-2.0.0.sh \
	| sed -e 's=DOWNLOAD "$$PROD_CLOUDFRONT_URL/libevent-2.1.8-stable.tar.gz" libevent-2.1.8-stable.tar.gz=DOWNLOAD https://github.com/libevent/libevent/releases/download/release-2.1.10-stable/libevent-2.1.10-stable.tar.gz libevent-2.1.10-stable.tar.gz=' \
	-e 's/libevent-2.1.8/libevent-2.1.10/' -e 's/-nc/-N/' \
	| bash

${HOME}/.c9/python3/bin/pylint: | ${HOME}/.c9
	ln -s $$(which pylint) $@

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
shell: $(addprefix ${HOME}/,.bash_profile .zshrc .config/fish/config.fish .gitignore .gitconfig .ssh/id_ed25519)

${HOME}/.bash_profile: bash_profile.sh
	cp $< $@
${HOME}/.zshrc: zshrc
	cp $< $@
${HOME}/.config/fish/config.fish: config.fish
	cp $< $@

${HOME}/.gitignore: gitignore
	cp $< $@
${HOME}/.gitconfig: gitconfig
	envsubst < $< > $@

${HOME}/.ssh/id_ed25519: id_ed25519
	chmod 600 $<
	ssh-keygen -pf $< -N ''
	chmod 400 $<
	mv $< $@
	git checkout HEAD -- $<

###########
# Scripts #
###########

SCRIPT_FILES := backup.sh ecr.sh lambda.sh ec2.py secret.fish
# https://www.gnu.org/software/make/manual/html_node/Text-Functions.html
SCRIPT_FILES := $(SCRIPT_FILES:%=${HOME}/.local/bin/%)
PYTHON_SITE_DIR := $(shell python -m site --user-site)
EC2_SSH_REQUIREMENTS := $(addprefix ${PYTHON_SITE_DIR}/,paramiko boto3 simple_term_menu.py)
$(info ${SCRIPT_FILES})
.PHONY: scripts
scripts: $(SCRIPT_FILES) ${HOME}/.local/bin/resize.sh ${PYTHON_SITE_DIR}/interactive_shell.py

${HOME}/.local/bin/resize.sh:
	wget -O $@ https://raw.githubusercontent.com/EugenMayer/parted-auto-resize/master/resize.sh
	chmod +x $@

~/.local/bin/%: %
	cp $< $@

${EC2_SSH_REQUIREMENTS}:
	pip install --user $(subst _,-,$(basename $(notdir ${EC2_SSH_REQUIREMENTS})))
${PYTHON_SITE_DIR}:
	mkdir -p $@
${PYTHON_SITE_DIR}/%: % | ${PYTHON_SITE_DIR} ${EC2_SSH_REQUIREMENTS}
	cp $< $@

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

##############
# Containers #
##############

# systemctl --user enable --now podman.socket
# sudo modprobe iptable-nat

# /usr/share/containers/containers.conf
# [engine]
# compose_providers = ["/home/linuxbrew/.linuxbrew/bin/docker-compose"]
# env = ["TMPDIR=/volatile/cache/tmp"]

# sudo touch /etc/containers/nodocker
# sudo semanage fcontext -a -e /var/lib/containers /volatile/containers
# sudo restorecon -R /volatile/containers

.PHONY: swap
swap: ${BLOB_DIR}/swap

${BLOB_DIR}/swap:
	sudo dd if=/dev/zero of=$@ bs=128M count=32
	sudo chmod 600 $@
	sudo mkswap $@
	sudo swapon $@
	sudo swapon -s
