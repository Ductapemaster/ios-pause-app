# The shield configuration extension cannot write to the app group

`ShieldConfigExtension` runs under a sandbox profile that refuses writes in the app group container. Taking the state lock is a write — `open(O_CREAT|O_RDWR)` on the lock file — so a shield render that began by taking the lock returned `EPERM` before reading anything, `RuleLookup.resolve` never ran, and the extension fell through to `ShieldPresentation.repair`: Instagram's shield read "Open Pause to repair this app" instead of "Next session: 1 of 3", with an inert "Done for today" button and no session count. Reads themselves are permitted, and the shield resolves once it stops taking the lock.

The denial comes from the sandbox profile iOS assigns to the shield configuration extension point, not from anything in the bundle's entitlements or signature.

## What the shield is supposed to show

`ShieldPresentation` (`Sources/Shared/RuleLookup.swift:89-116`) has four variants, all rendered through one `ShieldConfiguration` (`Sources/ShieldConfigExtension/ShieldConfigExtension.swift:51-63`). The allowed variant reads `"Next session: <n> of <limit>"` with a `"Pause to open"` button. Repair reads `"Open Pause to repair this app"` with a `"Done for today"` button, and is reached from an untyped `catch` covering eleven distinct failures — a nil application token, an absent or unreadable configuration, a lock failure, a token that matches no target, a missing runtime file, and others.

## The cause

The extension runs on every shield render and fails identically each time. From the unified log in `sysdiagnose_2026.08.20_14-17-19-0700`:

```
13:19:28.383  E  ShieldConfigExtension[42536:87182e] [com.koubalabs.pause.shieldconfig:shield]
                 Shield fell back to repair: Error Domain=NSPOSIXErrorDomain Code=1 "Operation not permitted"
```

Eight such entries span 12:36:22 to 13:43:46. The archive contains no `Shield resolved` entry at any point, so the extension has never completed a lookup.

`EPERM` is what `acquireFileLock` throws when `open(O_CREAT|O_RDWR|O_CLOEXEC)` on the lock file is denied (`Sources/Shared/AppGroupFileLock.swift:67-73`); `POSIXError(.EPERM)` bridges to exactly the observed `NSPOSIXErrorDomain Code=1`. Every logged entry carries the bridged `NSError` description rather than one of the extension's own `failedStage` strings, which rules out the two guarded paths — a nil application token and a missing configuration file.

The denial lands on the lock file's `open`, not on a read inside `withLock`: the same extension resolves normally once it reads the container's files without taking the lock (below). `AppGroupContainer().directoryURL()` succeeds, so `containerURL(forSecurityApplicationGroupIdentifier:)` resolves the path and the app group is visible to the process. Only writes inside it are refused.

### The sandbox profile is the discriminator

`ShieldActionExtension` runs the same sequence against the same container — `AppGroupFileLock`, `ConfigurationStore.load()`, `RuleLookup.resolve`, `RuntimeRepository` — and resolves normally, opening Pause and starting the countdown. The two extensions differ in the sandbox profile RunningBoard assigns them:

| Extension | Sandbox profile | App group file I/O |
|---|---|---|
| `ShieldActionExtension` | `plugin` | permitted |
| `ShieldConfigExtension` | `managed-settings-shield-configuration` | `EPERM` |

Both profiles appear in `runningboardd` extension-overlay entries in the same log. Identical code, identical entitlements, identical container: the extension point determines the profile, and the profile determines whether the file operations are allowed.

## Why the extension recorded nothing

`recordShieldDiagnostic` writes to `UserDefaults(suiteName: SharedIdentifiers.appGroup)` and returns silently when that suite is unavailable (`Sources/ShieldConfigExtension/ShieldConfigExtension.swift:15-21`). The same denial that forces the repair variant also blocks that write, so the shield's diagnostic key never appeared in shared preferences no matter how many times the shield fired.

The instrument was coupled to the failure it measured. Reading `shield-diagnostic-v1` could only ever report a failure that had not occurred. The `os_log` path shares nothing with the app group and carried the answer on the first read.

## Ruled out

- Cached shield configuration. The extension is invoked on every render, with a distinct log entry each time.
- A stale extension binary predating the diagnostic code. The running process emits the current log strings, and `ShieldConfigExtension.debug.dylib` in the installed build contains all of them.
- A missing App Group entitlement. `codesign -d --entitlements` on the embedded `Pause.app/PlugIns/ShieldConfigExtension.appex` shows `com.apple.security.application-groups` holding `group.com.koubalabs.pause` alongside `com.apple.developer.family-controls`, signed against team `<team-id>`.
- Leftover state from the other variant. The app group container was shared with `ios-pause-app-claude` and held its keys (`spikeLog`, `expectedEnd.interval16`, `shieldTapCount`, `targetScheme`). Deleting Pause destroyed the container; the symptom survived a clean install and re-add.
- A second Pause installed. Only `com.koubalabs.pause` is present.

## Consequence for the design

Phase 1 has the shield configuration extension compute what to display by taking a file lock and reading the configuration and runtime state from the app group. That is not permissible in this extension's sandbox, so the session count cannot be derived where it is currently derived. Whatever the shield displays has to be computed elsewhere and delivered through a channel the profile permits.

The denial is not a blanket one on reading. Shared preferences are a separate channel from the container's files, and the extension reads them: a counter written by the shield action extension into `UserDefaults(suiteName:)` was read back and rendered by the configuration extension on every press, while that extension's own writes to the same suite never landed. Reads through shared preferences survive where writes do not — see [the platform evidence note](screen-time-platform-evidence.md). Within the container the denial is direction-specific: reads of its files succeed, and the lock file's `open(O_CREAT|O_RDWR)` is refused.

The channel that redesign uses is the container's own files, read without the lock. `ShieldStateReader` loads the configuration and the runtime directly and never calls `AppGroupFileLock`, and the extension resolves: from `sysdiagnose_2026.08.20_22-41-03-0700`,

```
22:37:09.775  I  ShieldConfigExtension  Shield resolved: 1 session left today
22:40:39.376  I  ShieldConfigExtension  Shield resolved: That's all for today.
```

Both readings carry a real session count derived from those files, so reads of the container succeed under this profile. The denial is on the write, and `open(O_CREAT|O_RDWR)` on the lock file is a write — which is why taking the lock failed before any read was attempted, and why not taking it works.

## Method note

Each instrument reports something narrower than the question being asked of it, and the gap is silent. Establish what an instrument measures before reading meaning into its silence.

The instances met here:

- `log collect` needs USB and root.
- `devicectl` exposes only standard subdirectories of a container, never the root, so its listing is silent about `configuration.json` and the runtime files either way.
- Shared preferences do not flush on process exit, and this extension's writes to the app group suite do not land — so an absent key confounds "never ran," "lost the write," and "could not write at all."
- `strings` without `-a` skips the sections holding Swift literals, and in a debug-dylib build the `.appex` binary is a launcher stub whose literals live in a sibling `.debug.dylib`. Scanning the stub returns nothing for strings that are certainly present.
- A shell pipeline reports the exit status of its last command, so `devicectl … | tail` exits 0 after `devicectl` aborts on timeout.

A positive control catches all of these: run the instrument against something already known to be true, and treat a null result there as evidence about the instrument rather than the subject.
