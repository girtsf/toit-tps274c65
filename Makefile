# Uses the plain `toit` executable if available, falling back to `jag toit`.
# Override with e.g. `make TOIT="path/to/toit"`.
TOIT ?= $(shell command -v toit > /dev/null && echo toit || echo jag toit)

all: test

install-pkgs:
	$(TOIT) pkg install
	cd tests && $(TOIT) pkg install
	cd examples && $(TOIT) pkg install

test: install-pkgs
	@cd tests && for test in *-test.toit; do \
		echo "Running $$test"; \
		$(TOIT) run "$$test" || exit 1; \
	done

analyze: install-pkgs
	$(TOIT) analyze src/*.toit
	cd tests && $(TOIT) analyze *-test.toit
	cd examples && $(TOIT) analyze *.toit

.PHONY: all install-pkgs test analyze
