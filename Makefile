# Makefile

prefix ?= /tmp
bindir = $(prefix)/bin

BINARIES := spikot-wm spikot-placer

# SwiftLint (via SourceKitten) dlopens sourcekitdInProc.framework through a relative
# path, which only resolves against a full Xcode install. Pointing the framework
# search path at the active developer directory makes `make lint` work on a Command
# Line Tools-only install as well.
DEVELOPER_DIR := $(shell xcode-select -p)
SOURCEKIT_PATH := $(DEVELOPER_DIR)/usr/lib:$(DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain/usr/lib

.PHONY: build release install uninstall lint lint-fix clean

build:
	swift build

release: clean
	swift build --configuration release

install: release
	install -d "$(bindir)"
	for bin in $(BINARIES); do install ".build/release/$$bin" "$(bindir)"; done

uninstall:
	rm -f $(addprefix $(bindir)/,$(BINARIES))

lint:
	DYLD_FRAMEWORK_PATH="$(SOURCEKIT_PATH)" swiftlint lint Sources/

lint-fix:
	DYLD_FRAMEWORK_PATH="$(SOURCEKIT_PATH)" swiftlint lint --fix Sources/

clean:
	rm -rf .build
