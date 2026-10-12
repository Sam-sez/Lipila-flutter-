---
inclusion: always
---

# Lipila debugging rules

These rules apply to ALL work on this repo. Read them before proposing any change.

## The prime directive: evidence before patches

**Do NOT change BLE logic without runtime log evidence.**
The log comes from `AppLog` (visible in diagnostics screen → Copy all, and in `adb logcat | grep LIPILA`).
An assumption is not evidence. A compile error is not evidence of the runtime problem.
If you don't have a log that shows the failure, your first move is to get one.

## One change per iteration

Every iteration:
1. Has a single, named hypothesis (H1–H5 from HANDOVER.md, or a new one you've named).
2. Makes ONE code change that tests that hypothesis.
3. Ends with a CI build. The build id in the log must match the run number.
4. Updates DEBUG_LOG.md with evidence and outcome before the next iteration begins.

Do not bundle fixes. If you think two things are wrong, fix the one you have evidence for first.

## Commit conventions

```
fix: <what was wrong> (hypothesis H?)
diag: <what was instrumented>
ci: <what was changed in the workflow>
feat: <new feature>
```

Never leave the build broken. Use a branch for anything risky.

## The two-device constraint

Bong requires two physical Android devices for end-to-end testing.
With one device you can verify: permissions, adapter state, advertise start, scan start, ambient scan results.
You CANNOT verify: that two devices find each other, that the session token round-trips through the backend.
Don't claim Bong works until you have a two-device test log.

## Release vs debug

Always test BOTH APKs. The Kantemba precedent: debug worked, release silently failed because
R8 removed plugin classes loaded by name (ML Kit). The same class of bug affects flutter_blue_plus
and flutter_ble_peripheral. If debug works and release doesn't, the answer is ProGuard keep rules,
not `--no-shrink`.

## Manifest patch

`tool/patch_manifest.py` is the single source of truth for permissions.
Edit IT, not the workflow YAML directly, so local and CI builds stay in sync.
The script fails loudly if the patch doesn't apply — that's intentional.

## What to paste when asking for help

Always include:
- The full AppLog dump (Diagnostics → Copy all)
- The CI run number (matches BUILD_ID in the log)
- Whether the failure is debug, release, or both
- The exact error text (not a paraphrase)
