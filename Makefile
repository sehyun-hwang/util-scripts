#############
# Constants #
#############

BLOB_DIR := /volatile
ifndef HOME
$(error $$HOME is not set)
endif
ifndef USER
$(error $$USER is not set)
endif

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

${AWSCLI_DIR}/bin/aws:
	mkdir -p ${AWSCLI_DIR} && cd ${AWSCLI_DIR} \
	&& pip install -t . -U https://github.com/aws/aws-cli/archive/v2.zip \
	&& VERSION=$$(python -c 'import awscli; print(awscli.__version__)') \
	&& echo $$VERSION \
	&& docker create --name awscli amazon/aws-cli:$$VERSION \
	&& docker cp awscli:/usr/local/aws-cli/v2/$$VERSION/dist/awscli/data/ac.index awscli/data/ \
	&& docker rm awscli

${HOME}/.local/bin/aws: ${AWSCLI_DIR}/bin/aws
	echo '#!/bin/bash' > $@
	echo 'PYTHONPATH=${AWSCLI_DIR} python -m awscli "$$@"' >> $@
	chmod +x $@
	aws --version

#######################
# Shell Configuration #
#######################

.PHONY: shell
shell: ${HOME}/.bash_profile ${HOME}/.config/fish/config.fish ${HOME}/.gitignore ${HOME}/.gitconfig

${HOME}/.bash_profile:
	cp bash_profile $@

${HOME}/.config/fish/config.fish: ${HOME}/.local/bin/aws
	# https://github.com/aws/aws-cli/issues/1079#issuecomment-541997810
	echo "complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); PYTHONPATH=${AWSCLI_DIR} ${AWSCLI_DIR}/bin/aws_completer | sed \'s/ $//\'; end)'" > $@

${HOME}/.gitignore:
	cp gitignore $@

${HOME}/.gitconfig: ${HOME}/.gitignore
	envsubst < gitconfig > $@

###########
# Scripts #
###########

SCRIPT_FILES := $(addprefix ${HOME}/.local/bin/,backup.sh ecr.sh lambda.sh)
PYTHON_SITE_DIR := $(shell python -m site --user-site)
EC2_SSH_FILES := $(addprefix ${PYTHON_SITE_DIR}/,ec2.py interactive_shell.py)
EC2_SSH_REQUIREMENTS := $(addprefix ${PYTHON_SITE_DIR}/,${EC2_SSH_REQUIREMENTS})

.PHONY: scripts
scripts: ${HOME}/.local/bin/resize.sh ${SCRIPT_FILES} ${EC2_SSH_FILES}

${HOME}/.local/bin/resize.sh:
	wget -O $@ https://raw.githubusercontent.com/EugenMayer/parted-auto-resize/master/resize.sh

${EC2_SSH_REQUIREMENTS}:
	pip install $(notdir ${EC2_SSH_REQUIREMENTS})

${EC2_SSH_FILES}: | ${EC2_SSH_REQUIREMENTS}

${SCRIPT_FILES} ${EC2_SSH_FILES}:
	cp $(notdir $@) $@
