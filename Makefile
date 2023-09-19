# Makefile

prefix ?= /tmp/
bindir = $(prefix)/bin

build:
	swift build

release:
	swift build --configuration release

install: release
	install -d "$(bindir)"
	install ".build/release/spikot-win" "$(bindir)"

uninstall:
	rm -rf "$(bindir)/spikot-win"

clean:
	rm -rf .build
