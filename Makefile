.DEFAULT_GOAL := stylua-run

ifeq ($(shell uname -s),Darwin)
    UNAME ?= MACOS
else
    UNAME ?= LINUX
endif

NVIM_VERSION := v0.12.6
NVIM_PLATFORM_MACOS := macos-$(shell uname -m)
NVIM_PLATFORM_LINUX := linux-$(subst aarch64,arm64,$(shell uname -m))
TEST_DEPS := .deps/neovim/$(NVIM_VERSION)
NVIM ?= $(TEST_DEPS)/bin/nvim
TEST_FILE ?= test

$(TEST_DEPS)/bin/nvim:
	mkdir -p "$(TEST_DEPS)"
	curl -fsSL --output "$(TEST_DEPS)/nvim.tar.gz" \
		https://github.com/neovim/neovim/releases/download/$(NVIM_VERSION)/nvim-$(NVIM_PLATFORM_$(UNAME)).tar.gz
	tar -xzf "$(TEST_DEPS)/nvim.tar.gz" --strip-components=1 -C "$(TEST_DEPS)"

$(TEST_DEPS)/test/functional/testnvim.lua:
	mkdir -p "$(TEST_DEPS)"
	curl -fsSL --output "$(TEST_DEPS)/source.tar.gz" \
		https://github.com/neovim/neovim/archive/refs/tags/$(NVIM_VERSION).tar.gz
	tar -xzf "$(TEST_DEPS)/source.tar.gz" --strip-components=1 -C "$(TEST_DEPS)"

.PHONY: test
test: $(TEST_DEPS)/test/functional/testnvim.lua $(filter $(TEST_DEPS)/%,$(NVIM))
	NVIM_LOG_FILE=.deps/nvim.log "$(NVIM)" --clean \
		-l test/runner.lua "$(TEST_DEPS)" "$(TEST_FILE)"

STYLUA_PLATFORM_MACOS := macos-aarch64
STYLUA_PLATFORM_LINUX := linux-x86_64
STYLUA_PLATFORM := $(STYLUA_PLATFORM_$(UNAME))

STYLUA_VERSION := v0.18.2
STYLUA_ZIP := stylua-$(STYLUA_PLATFORM).zip
STYLUA_URL_BASE := https://github.com/JohnnyMorganz/StyLua/releases/download
STYLUA_URL := $(STYLUA_URL_BASE)/$(STYLUA_VERSION)/$(STYLUA_ZIP)

.INTERMEDIATE: $(STYLUA_ZIP)
$(STYLUA_ZIP):
	wget $(STYLUA_URL)

stylua: $(STYLUA_ZIP)
	unzip $<

.PHONY: stylua-check
stylua-check: stylua
	./stylua --check lua/**/*.lua

.PHONY: stylua-run
stylua-run: stylua
	./stylua lua/**/*.lua lua/*.lua
