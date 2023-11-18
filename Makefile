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
cloud9:
	curl https://d3kgj69l4ph6w4.cloudfront.net/static/c9-install-2.0.0.sh \
	| sed -e 's=DOWNLOAD "$$PROD_CLOUDFRONT_URL/libevent-2.1.8-stable.tar.gz" libevent-2.1.8-stable.tar.gz=DOWNLOAD https://github.com/libevent/libevent/releases/download/release-2.1.10-stable/libevent-2.1.10-stable.tar.gz libevent-2.1.10-stable.tar.gz=' \
	-e 's/libevent-2.1.8/libevent-2.1.10/' -e 's/-nc/-N/' \
	| bash

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
	mkdir -p ${BLOB_DIR}/vscode ~/.vscode-server
	ln -s ${BLOB_DIR}/vscode ~/.vscode
	ln -s ${BLOB_DIR}/vscode-server ~/.vscode-server

.PHONY: code-tunnel
code-tunnel:
	systemd-run -p CPUQuota=100% -p MemoryMax=2G -p MemorySwapMax=500M --user --scope code tunnel

###########
# AWS CLI #
###########

AWSCLI_DIR := ${BLOB_DIR}/src/awscli
AWSCLI_WHEEL := $(wildcard ${AWSCLI_DIR}/awscli-*-py3-none-any.whl)
ifeq (${AWSCLI_WHEEL},)
AWSCLI_WHEEL := ${AWSCLI_DIR}/awscli-$(shell curl -s https://api.github.com/repos/aws/aws-cli/tags'?per_page=1' | jq -r .[0].name)-py3-none-any.whl
endif

${AWSCLI_WHEEL}:
	mkdir -p ${AWSCLI_DIR} && cd ${AWSCLI_DIR} \
	&& pip wheel https://github.com/aws/aws-cli/archive/v2.zip --no-deps

${AWSCLI_DIR}/bin/aws: ${AWSCLI_WHEEL}
	cd ${AWSCLI_DIR} \
	&& pip install -t . $< \
	&& VERSION=$$(python -c 'import awscli; print(awscli.__version__)') \
	&& echo $$VERSION \
	&& docker create --name awscli amazon/aws-cli:$$VERSION \
	&& docker cp awscli:/usr/local/aws-cli/v2/$$VERSION/dist/awscli/data/ac.index awscli/data/ \
	&& docker rm awscli

${HOME}/.local/bin/aws: | ${AWSCLI_DIR}/bin/aws
	echo '#!/bin/bash' > $@
	echo 'PYTHONPATH=${AWSCLI_DIR} python -m awscli "$$@"' >> $@
	chmod +x $@
	aws --version

##############
# Containers #
##############

# systemctl --user enable --now podman.socket
# mkdir /volatile/containers
# ln -s /volatile/containers /home/ec2-user/.local/share/containers
# sudo modprobe iptable-nat

#######################
# Shell Configuration #
#######################

.PHONY: shell
shell: ${HOME}/.bash_profile ${HOME}/.config/fish/config.fish ${HOME}/.gitignore ${HOME}/.gitconfig ${HOME}/.ssh/id_ed25519

${HOME}/.bash_profile: bash_profile.sh
	cp $< $@

${HOME}/.config/fish/config.fish: config.fish ${HOME}/.local/bin/aws
	cp $< $@
	# https://github.com/aws/aws-cli/issues/1079#issuecomment-541997810
	echo "complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); PYTHONPATH=${AWSCLI_DIR} ${AWSCLI_DIR}/bin/aws_completer | sed \'s/ $//\'; end)'" >> $@

${HOME}/.gitignore:
	cp gitignore $@

${HOME}/.gitconfig: ${HOME}/.gitignore
	envsubst < gitconfig > $@

${HOME}/.ssh/id_ed25519: id_ed25519
	chmod 600 $<
	ssh-keygen -pf $< -N ''
	chmod 400 $<
	mv $< $@
	git checkout HEAD -- $<

###########
# Scripts #
###########

SCRIPT_FILES := $(addprefix ${HOME}/.local/bin/,backup.sh ecr.sh lambda.sh)
PYTHON_SITE_DIR := $(shell python -m site --user-site)
EC2_SSH_FILES := $(addprefix ${PYTHON_SITE_DIR}/,ec2.py interactive_shell.py)
EC2_SSH_REQUIREMENTS := $(addprefix ${PYTHON_SITE_DIR}/,paramiko boto3 simple_term_menu)

.PHONY: scripts backup
scripts: ${HOME}/.local/bin/resize.sh ${SCRIPT_FILES} ${EC2_SSH_FILES}

${HOME}/.local/bin/resize.sh:
	wget -O $@ https://raw.githubusercontent.com/EugenMayer/parted-auto-resize/master/resize.sh
	chmod +x $@

${EC2_SSH_REQUIREMENTS}:
	pip install $(notdir ${EC2_SSH_REQUIREMENTS})

${EC2_SSH_FILES}: | ${EC2_SSH_REQUIREMENTS}

${SCRIPT_FILES} ${EC2_SSH_FILES}:
	cp $(notdir $@) $@

##########
# Backup #
##########
$(shell	mkdir -p backup)

.PHONY: backup
backup: backup/ssh-config.txt backup/fish.json
	dnf history > backup/dnf.txt
	brew leaves > backup/brew.txt
	pnpm ls -g > backup/pnpm.txt

backup/ssh-config.txt: ${HOME}/.ssh/config
	cp $< $@
backup/fish.json: ${HOME}/.local/share/fish/fish_history
	cp $< $@
