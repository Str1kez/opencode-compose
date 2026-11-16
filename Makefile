.PHONY: all bump-uv

all:
	./scripts/setup.sh

# Pins uv for the python profile: docker/uv-requirements.txt gets the version and the
# sha256 of every file PyPI publishes for it, so pip in the image build accepts only those.
# Needs uv on the host. Usage: make bump-uv UV_VERSION=0.14.0
bump-uv:
	@test -n "$(UV_VERSION)" || { echo "usage: make bump-uv UV_VERSION=<version>" >&2; exit 2; }
	@# stdout, not --output-file: an existing output file makes uv reuse its hashes.
	@# Through a temp file, so a failed lookup leaves the current pin as it is.
	echo "uv==$(UV_VERSION)" | uv pip compile - --generate-hashes --quiet \
		--custom-compile-command "make bump-uv UV_VERSION=$(UV_VERSION)" \
		> docker/uv-requirements.txt.tmp \
		|| { rm -f docker/uv-requirements.txt.tmp; exit 1; }
	mv docker/uv-requirements.txt.tmp docker/uv-requirements.txt
