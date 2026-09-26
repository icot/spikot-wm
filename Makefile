# Makefile

prefix ?= /tmp
bindir = $(prefix)/bin

BINARIES := spikot-wm spikot-placer

# The one place the version is written down is Sources/StateCore/Version.swift.
VERSION_FILE := Sources/StateCore/Version.swift
VERSION := $(shell sed -n 's/^public let spikotVersion = "\(.*\)"$$/\1/p' $(VERSION_FILE))

# SwiftLint (via SourceKitten) dlopens sourcekitdInProc.framework through a relative
# path, which only resolves against a full Xcode install. Pointing the framework
# search path at the active developer directory makes `make lint` work on a Command
# Line Tools-only install as well.
DEVELOPER_DIR := $(shell xcode-select -p)
SOURCEKIT_PATH := $(DEVELOPER_DIR)/usr/lib:$(DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain/usr/lib

.PHONY: build release install uninstall lint lint-fix version version-check clean

build:
	swift build

release: clean
	swift build --configuration release

install: release
	install -d "$(bindir)"
	for bin in $(BINARIES); do install ".build/release/$$bin" "$(bindir)"; done

uninstall:
	rm -f $(addprefix $(bindir)/,$(BINARIES))

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
