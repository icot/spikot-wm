# Makefile

prefix ?= /tmp/
bindir = $(prefix)/bin

build:
	swift build

release: clean
	swift build --configuration release

install: release
	install -d "$(bindir)"
	install ".build/release/spikot-wm" "$(bindir)"

uninstall:
	rm -rf "$(bindir)/spikot*"
lint:
	swiftlint Sources/

clean:
	rm -rf .build
