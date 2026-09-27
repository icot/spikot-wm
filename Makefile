# Makefile

# Defaults to ~/.local because that is where the CLI is actually used from: the skhd
# LaunchAgent puts ~/.local/bin on its PATH. The old /tmp default was a footgun that
# produced a literal './~' directory when someone quoted the tilde.
prefix ?= $(HOME)/.local
bindir = $(prefix)/bin
appdir ?= $(HOME)/Applications

BINARIES := spikot-wm spikot-placer

# The agent ships as an .app, not a bare binary. TCC keys its Accessibility grant on the
# bundle identifier plus the designated requirement, so both are fixed here.
APP_NAME := SpikotWM
APP_ID := org.traf.spikot-wm
APP_BUNDLE := .build/$(APP_NAME).app
AGENT_LABEL := org.traf.spikot-agent
LAUNCHAGENT_DIR := $(HOME)/Library/LaunchAgents
LOG_DIR := $(HOME)/Library/Logs/spikot-wm

# The one place the version is written down is Sources/StateCore/Version.swift.
VERSION_FILE := Sources/StateCore/Version.swift
VERSION := $(shell sed -n 's/^public let spikotVersion = "\(.*\)"$$/\1/p' $(VERSION_FILE))

# SwiftLint (via SourceKitten) dlopens sourcekitdInProc.framework through a relative
# path, which only resolves against a full Xcode install. Pointing the framework
# search path at the active developer directory makes `make lint` work on a Command
# Line Tools-only install as well.
DEVELOPER_DIR := $(shell xcode-select -p)
SOURCEKIT_PATH := $(DEVELOPER_DIR)/usr/lib:$(DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain/usr/lib

.PHONY: build release bundle install install-app install-agent uninstall-agent uninstall test lint lint-fix version version-check clean

build:
	swift build

# swift-testing's macros are a compiler plugin. SwiftPM finds the Testing framework but
# does not pass the plugin to the test target on a Command Line Tools-only install, so
# `swift test` fails with "plugin for module 'TestingMacros' not found". Loading it
# explicitly fixes that; the path is derived so this keeps working under a real Xcode.
TESTING_MACROS := $(DEVELOPER_DIR)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib

test:
	swift test $(if $(wildcard $(TESTING_MACROS)),-Xswiftc -load-plugin-library -Xswiftc $(TESTING_MACROS),)

release: clean
	swift build --configuration release

# Ad-hoc signed with an explicit identifier-only designated requirement.
#
# Without -r, an ad-hoc signature's designated requirement is `cdhash H"..."`, which pins
# the exact binary. Measured: two builds differing by one string literal produced different
# cdhashes, so every rebuild would be a different principal to TCC and the Accessibility
# grant would have to be given again. With -r the requirement is just the identifier and
# stays byte-identical across rebuilds.
#
# A self-signed certificate would also work, but `security find-identity -v -p codesigning`
# reports 0 identities on this machine and creating one is a manual Keychain Access step.
bundle: release
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	sed -e 's/<string>0\.0\.0<\/string>/<string>$(VERSION)<\/string>/g' \
		Packaging/Info.plist > "$(APP_BUNDLE)/Contents/Info.plist"
	install ".build/release/spikot-agent" "$(APP_BUNDLE)/Contents/MacOS/spikot-agent"
	codesign --force --sign - --identifier "$(APP_ID)" \
		-r='designated => identifier "$(APP_ID)"' "$(APP_BUNDLE)"
	@codesign -d --requirements - "$(APP_BUNDLE)" 2>&1 | grep designated

install: release
	install -d "$(bindir)"
	for bin in $(BINARIES); do install ".build/release/$$bin" "$(bindir)"; done

install-app: bundle
	install -d "$(appdir)"
	rm -rf "$(appdir)/$(APP_NAME).app"
	cp -R "$(APP_BUNDLE)" "$(appdir)/"
	@echo "installed $(appdir)/$(APP_NAME).app"

# Registers the agent to start at login. Separate from install-app so the bundle can be
# tried by hand before anything is made permanent.
#
# bootout first and ignore its failure: bootstrap refuses if the label is already loaded,
# and there is no idempotent form.
install-agent: install-app
	install -d "$(LAUNCHAGENT_DIR)" "$(LOG_DIR)"
	sed -e 's|@APP@|$(appdir)/$(APP_NAME).app|g' -e 's|@LOGDIR@|$(LOG_DIR)|g' \
		Packaging/$(AGENT_LABEL).plist > "$(LAUNCHAGENT_DIR)/$(AGENT_LABEL).plist"
	-launchctl bootout gui/$(shell id -u)/$(AGENT_LABEL) 2>/dev/null
	launchctl bootstrap gui/$(shell id -u) "$(LAUNCHAGENT_DIR)/$(AGENT_LABEL).plist"
	@echo "agent registered; logs in $(LOG_DIR)"
	@launchctl print gui/$(shell id -u)/$(AGENT_LABEL) 2>/dev/null | grep -E '^\s*(state|pid) =' || true

uninstall-agent:
	-launchctl bootout gui/$(shell id -u)/$(AGENT_LABEL) 2>/dev/null
	rm -f "$(LAUNCHAGENT_DIR)/$(AGENT_LABEL).plist"
	@echo "agent unregistered"

uninstall: uninstall-agent
	rm -f $(addprefix $(bindir)/,$(BINARIES))
	rm -rf "$(appdir)/$(APP_NAME).app"

version:
	@printf '%s\n' "$(VERSION)"

# Asserts the version constant matches the newest git tag. Run at release time,
# after committing the bump and tagging it -- not from `build`, where an
# in-progress bump would fail for no reason.
version-check:
	@test -n "$(VERSION)" || { echo "version-check: could not read spikotVersion from $(VERSION_FILE)" >&2; exit 1; }
	@tag=$$(git describe --tags --abbrev=0 2>/dev/null || true); \
	if [ -z "$$tag" ]; then echo "version-check: no git tags found" >&2; exit 1; fi; \
	if [ "v$(VERSION)" != "$$tag" ]; then \
		echo "version-check: spikotVersion is $(VERSION) (expects tag v$(VERSION)) but newest tag is $$tag" >&2; \
		exit 1; \
	fi; \
	echo "version-check: $(VERSION) matches $$tag"

lint:
	DYLD_FRAMEWORK_PATH="$(SOURCEKIT_PATH)" swiftlint lint Sources/

lint-fix:
	DYLD_FRAMEWORK_PATH="$(SOURCEKIT_PATH)" swiftlint lint --fix Sources/

clean:
	rm -rf .build
