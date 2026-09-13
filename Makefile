SHELL := /bin/sh

PREFIX ?= $(HOME)/.local
XDG_DATA_HOME ?= $(PREFIX)/share
INSTALL_ROOT ?= $(XDG_DATA_HOME)/careershopper
AGENTS_DIR ?= $(HOME)/.agents

.DEFAULT_GOAL := help
.NOTPARALLEL:

.PHONY: help get generate format analyze test test-native check run build-linux build-agent install-desktop install-agent install mcp-info

help:
	@echo "CareerShopper development targets"
	@echo "  make run          Run the Flutter desktop app"
	@echo "  make check        Format check, analyze, and test"
	@echo "  make test-native  Test Linux tray behavior (requires a GTK display)"
	@echo "  make build-linux  Build a release Linux desktop bundle"
	@echo "  make build-agent  Build the native MCP/plugin helper"
	@echo "  make install      Install the desktop app, MCP plugin, and Skill"
	@echo "  make mcp-info     Print the installed MCP command"

get:
	flutter pub get

generate: get
	dart run build_runner build

format:
	dart format --output=none --set-exit-if-changed bin lib test tool

analyze: get
	dart analyze

test: get
	flutter test

test-native:
	cmake -S test/linux -B build/native-tests
	cmake --build build/native-tests
	dbus-run-session -- ctest --test-dir build/native-tests --output-on-failure

check: format analyze test

run: get
	flutter run -d linux

build-linux: get
	flutter build linux --release

build-agent: get
	dart run tool/build_agent_plugin.dart

install-desktop: build-linux
	dart run tool/install_linux_desktop.dart --bundle "build/linux/x64/release/bundle" --prefix "$(PREFIX)" --data-home "$(XDG_DATA_HOME)"

install-agent: build-agent
	dart run tool/install_agent_integration.dart --install-root "$(INSTALL_ROOT)" --agents-dir "$(AGENTS_DIR)"

install: install-desktop install-agent
	@echo "CareerShopper installed for the current user."
	@echo "Launch it from your application menu or run $(PREFIX)/bin/careershopper."

mcp-info:
	@echo "$(INSTALL_ROOT)/agent-plugin/bin/careershopper-agent mcp"
