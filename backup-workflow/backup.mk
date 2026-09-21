.PHONY: backup
BACKUP_DIR ?= backup
VSCODE_SETTINGS ?= $(firstword $(wildcard $(HOME)/.vscode-server/data/Machine/settings.json))

backup:
	@mkdir -p "$(BACKUP_DIR)"
	@set -e; \
	if command -v dnf >/dev/null 2>&1; then dnf history > "$(BACKUP_DIR)/dnf.txt"; fi; \
	if command -v apt-mark >/dev/null 2>&1; then apt-mark showmanual > "$(BACKUP_DIR)/apt.txt"; fi; \
	if command -v brew >/dev/null 2>&1; then \
		brew leaves > "$(BACKUP_DIR)/brew-leaves.txt"; \
		brew list --cask > "$(BACKUP_DIR)/brew-casks.txt"; \
	fi; \
	if command -v pnpm >/dev/null 2>&1; then pnpm ls -g > "$(BACKUP_DIR)/pnpm.txt"; fi; \
	if command -v yarn >/dev/null 2>&1; then yarn global list > "$(BACKUP_DIR)/yarn.txt"; fi; \
	if test -f "$(HOME)/.ssh/config"; then cp "$(HOME)/.ssh/config" "$(BACKUP_DIR)/ssh-config.txt"; fi; \
	settings='$(VSCODE_SETTINGS)'; \
	if test -z "$$settings" && test -f "$(HOME)/Library/Application Support/Code/User/settings.json"; then \
		settings="$(HOME)/Library/Application Support/Code/User/settings.json"; \
	fi; \
	if test -z "$$settings" && test -f "$(HOME)/.config/Code/User/settings.json"; then \
		settings="$(HOME)/.config/Code/User/settings.json"; \
	fi; \
	if test -n "$$settings" && test -f "$$settings"; then cp "$$settings" "$(BACKUP_DIR)/vscode.jsonc"; fi
