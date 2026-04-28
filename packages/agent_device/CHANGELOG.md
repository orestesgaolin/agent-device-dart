## 0.0.2

**Features**

- **find**: enhance find command to support selector DSL, locator tokens, and substring queries

**Bug Fixes**

- implement retry logic for Android UiAutomation conflicts

**Refactor**

- migrate to cli_logger

## 0.0.1 (preview)

Initial Dart port of `agent-device` (TS upstream). There are some changes to the upstream API to adjust it to the Dart workflow. The main differences are:

- no device session
- slight differences in the API
- way of bundling the native executables with the package
