# Casement — builds with the Xcode Command Line Tools alone.
# swift-testing's macros need the plugin path spelled out when the Command Line Tools are the
# selected toolchain; with Xcode selected they are found without it. Deriving the path from
# `xcode-select -p` and adding it only when it is there means one command works either way, so
# what you run locally is what CI runs.
TESTING_PLUGINS := $(shell xcode-select -p 2>/dev/null)/usr/lib/swift/host/plugins/testing
SWIFT_TEST_FLAGS = $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS),)

.PHONY: build app run demo test e2e e2e-media perf snapshots motion-snapshots settings-snapshots check install release clean

build:            ## Debug build of the app and CLI
	swift build

app:              ## Release Casement.app in build/ (ad-hoc signed)
	scripts/bundle.sh

run: app          ## Build and launch Casement.app
	open build/Casement.app

demo:             ## Launch with demo content (debug build)
	swift build --product Casement && .build/debug/Casement --demo

test:             ## Unit + system tests (swift-testing)
	swift test $(SWIFT_TEST_FLAGS)

e2e: app          ## End-to-end tests against the real app (isolated config, own port)
	python3 Tests/E2E/e2e.py

e2e-media: app    ## …plus the MediaRemote bridge test (skips itself if something is playing)
	CASEMENT_E2E_MEDIA=1 python3 Tests/E2E/e2e.py

perf: app         ## CPU per island state against the performance budget
	scripts/perf.sh

snapshots:        ## Render every island state to build/snapshots/*.png
	swift build --product Casement && .build/debug/Casement --snapshot build/snapshots

motion-snapshots: ## Render each island transition as a contact sheet to build/motion-snapshots/*.png
	swift build --product Casement && .build/debug/Casement --snapshot-motion build/motion-snapshots

settings-snapshots: ## Render every Settings page, light and dark, to build/settings-snapshots/*.png
	swift build --product Casement && .build/debug/Casement --settings-snapshot build/settings-snapshots

check: test e2e perf  ## Everything

install: app      ## Copy to /Applications and link the CLI (asks nothing; review first)
	rm -rf /Applications/Casement.app && cp -R build/Casement.app /Applications/
	@echo "CLI: ln -sf /Applications/Casement.app/Contents/MacOS/casementctl /opt/homebrew/bin/casementctl"

release:          ## Zip, checksum and notes for the newest CHANGELOG version (PUBLISH=1 creates the GitHub release)
	scripts/release.sh $(if $(PUBLISH),--publish,)

clean:
	rm -rf .build build
