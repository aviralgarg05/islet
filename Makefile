# Islet — builds with the Xcode Command Line Tools alone.
SWIFT_TEST_FLAGS = -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

.PHONY: build app run demo test e2e e2e-media perf snapshots motion-snapshots settings-snapshots check install release clean

build:            ## Debug build of the app and CLI
	swift build

app:              ## Release Islet.app in build/ (ad-hoc signed)
	scripts/bundle.sh

run: app          ## Build and launch Islet.app
	open build/Islet.app

demo:             ## Launch with demo content (debug build)
	swift build --product Islet && .build/debug/Islet --demo

test:             ## Unit + system tests (swift-testing)
	swift test $(SWIFT_TEST_FLAGS)

e2e: app          ## End-to-end tests against the real app (isolated config, own port)
	python3 Tests/E2E/e2e.py

e2e-media: app    ## …plus the MediaRemote bridge test (skips itself if something is playing)
	ISLET_E2E_MEDIA=1 python3 Tests/E2E/e2e.py

perf: app         ## CPU per island state against the performance budget
	scripts/perf.sh

snapshots:        ## Render every island state to build/snapshots/*.png
	swift build --product Islet && .build/debug/Islet --snapshot build/snapshots

motion-snapshots: ## Render each island transition as a contact sheet to build/motion-snapshots/*.png
	swift build --product Islet && .build/debug/Islet --snapshot-motion build/motion-snapshots

settings-snapshots: ## Render every Settings page, light and dark, to build/settings-snapshots/*.png
	swift build --product Islet && .build/debug/Islet --settings-snapshot build/settings-snapshots

check: test e2e perf  ## Everything

install: app      ## Copy to /Applications and link the CLI (asks nothing; review first)
	rm -rf /Applications/Islet.app && cp -R build/Islet.app /Applications/
	@echo "CLI: ln -sf /Applications/Islet.app/Contents/MacOS/isletctl /opt/homebrew/bin/isletctl"

release:          ## Zip, checksum and notes for the newest CHANGELOG version (PUBLISH=1 creates the GitHub release)
	scripts/release.sh $(if $(PUBLISH),--publish,)

clean:
	rm -rf .build build
