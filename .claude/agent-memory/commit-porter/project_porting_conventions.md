---
name: Porting conventions
description: Commit message format, registry location, and test run flags for this project
type: project
---

## Commit message format

```
port: <upstream message> (<upstream hash 8 chars>)

Port of upstream commit <full-hash> ("<upstream message>").

<bullets describing changes>

Deviations from upstream:
- <list any differences>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

Use plain `git commit` — no `-c user.email` or `-c user.name` overrides.

## Registry location

`PORTING_PLAN.md` at the repo root — section "8. Status / Changelog".
Append a dated bullet `- **YYYY-MM-DD**: ...` above the `(Append dated entries below...)` sentinel.

## Test flags

```sh
dart test packages/agent_device/test/ --exclude-tags live
```
The one pre-existing failure is `perf_xml_test.dart: parseIosDevicePerfXml (setUpAll)` — missing
fixture file, unrelated to any port work.

## dart analyze

Run `dart analyze packages/agent_device/` — only `info` level should remain (pre-existing lints
in fixture-app live tests and `prefer_const_constructors` now that RawSnapshotNode is non-const).
Zero `error` or `warning` is the green bar.

**Why:** These conventions ensure registry entries and commits are consistent and the CI pipeline passes.
**How to apply:** Follow for every upstream commit port.
