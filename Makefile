.PHONY: get analyze format test check clean

get:
	dart pub get

analyze:
	dart analyze

format:
	dart format .

test:
	dart test packages/agent_device

check: analyze test

clean:
	rm -rf packages/*/.dart_tool packages/*/build .dart_tool
