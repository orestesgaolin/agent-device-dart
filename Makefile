.PHONY: get analyze format test check clean compile compile-clean

get:
	dart pub get

analyze:
	dart analyze

format:
	dart format .

test:
	dart test packages/agent_device

check: analyze test

# Build a standalone native binary at dist/agent-device. Side-by-side
# `ad` is a symlink so users can pick whichever spelling they prefer.
# Run `make compile` after every release; the binary embeds the SDK so
# it has no Dart-runtime dependency on the host.
compile:
	@mkdir -p dist
	dart compile exe packages/agent_device/bin/agent_device.dart -o dist/agent-device
	ln -sf agent-device dist/ad
	@echo "built: $$(pwd)/dist/agent-device  ($$(du -h dist/agent-device | cut -f1))"

compile-clean:
	rm -rf dist

clean:
	rm -rf packages/*/.dart_tool packages/*/build .dart_tool dist
