# Install copies this bundle to <share>/bundles/basic, where `x -l` looks: a bundle is
# installed when its files are there. No registry, no database.

X ?= x

# The version is derived from git describe, never committed: bundle.xon declares
# what this lang requires; the installed artifact carries what it is.
LANG_VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
SHARE := $(if $(PREFIX),$(PREFIX)/share/x,$(shell $(X) --share-dir))
DEST  := $(SHARE)/bundles/basic

# What a consumer needs to run the lang: the declaration and the modules,
# the entry among them.  Not the suite, not the tooling, not CI.
PAYLOAD := bundle.xon lib

.PHONY: install
install: ## Install into <share>/bundles/basic
	@test -n "$(SHARE)" || { echo "x-basic: cannot find an x tree -- set PREFIX or X" >&2; exit 1; }
	@test -d "$(SHARE)" || { echo "x-basic: no x tree at $(SHARE)" >&2; exit 1; }
	rm -rf "$(DEST)"
	mkdir -p "$(DEST)"
	cp -R $(PAYLOAD) "$(DEST)/"
	printf '%s\n' '$(LANG_VERSION)' > "$(DEST)/version"
	@echo "x-basic: installed to $(DEST)"
	@echo "x-basic: writing the boot image"
	"$(X)" --image -l basic || true
	@echo "x-basic: try  x -l basic"

.PHONY: uninstall
uninstall: ## Remove it again
	rm -rf "$(DEST)"
	@echo "x-basic: removed $(DEST)"

.PHONY: test
test: ## Run the spec suite (every failure is loud)
	X="$(X)" sh tests/spec-runner.sh

.PHONY: check
check: ## Run the suite against tests/contract/known-failures.txt -- what CI gates on
	X="$(X)" sh tests/spec-gate.sh

.PHONY: card
card: ## Hold docs/card.md to the card format and run its programs
	X_BUNDLE_DIR="$${X_BUNDLE_DIR:-$(CURDIR)/..}" BUNDLE=. X="$(X)" \
		sh "$${CARD_SH:-$$("$(X)" --share-dir)/tools/bundle-kit/card.sh}"

.PHONY: help
help: ## Show targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[32m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
