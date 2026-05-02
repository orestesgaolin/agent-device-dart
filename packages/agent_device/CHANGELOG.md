## 0.0.4

**Features**

- add Android frame health perf metrics (port of 0c7e48d7)
- add iOS frame perf sampling (port of cff8bd81)

## 0.0.3

**Features**

- sort devices by boot status in \_listAllPlatforms method

**Bug Fixes**

- handle iOS keyboard Done dismiss controls (port of bbb1d363)
- set application debuggable to false in AndroidManifest.xml
- Cache Android helper installs (port of 3fee9d6d)

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
