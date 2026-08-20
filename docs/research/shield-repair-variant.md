# The shield renders its repair variant

Instagram's shield reads "Open Pause to repair this app" instead of "Next session: 1 of 3", carries the repair variant's inert "Done for today" button label, and shows no session count. All three symptoms are one fact: `ShieldConfigExtension` produced `ShieldPresentation.repair` rather than the allowed variant.

## What the shield is supposed to show

`ShieldPresentation` (`Sources/Shared/RuleLookup.swift:89-116`) has four variants, all rendered through one `ShieldConfiguration` (`Sources/ShieldConfigExtension/ShieldConfigExtension.swift:51-63`). The allowed variant reads `"Next session: <n> of <limit>"` with a `"Pause to open"` button. Repair reads `"Open Pause to repair this app"` with a `"Done for today"` button, and is reached from an untyped `catch` covering eleven distinct failures — a nil application token, an absent or unreadable configuration, a lock failure, a token that matches no target, a missing runtime file, and others.

## Established

- **The tap path works while the render path does not.** The action extension opens Pause and starts the countdown, which it only does after `RuleLookup.resolve` succeeds and returns `.allowed` (`Sources/ShieldActionExtension/ShieldActionExtension.swift:19-41`). The stored configuration is therefore readable and correct.
- **The two extensions differ in one step.** The action extension receives an `ApplicationToken` directly; the config extension receives an `Application` and must unwrap `application.token`, which is the first thing that can throw (`ShieldConfigExtension.swift:25-29`).
- **Neither extension crashes.** No crash report exists for any Pause extension.
- **All three extension points are registered correctly**, verified in the built `Info.plist`s: `com.apple.ManagedSettingsUI.shield-configuration-service`, `com.apple.ManagedSettings.shield-action-service`, `com.apple.deviceactivity.monitor-extension`.
- **Writes from the app reach shared preferences and can be read from a connected Mac.** `app-diagnostic-v1` was written at 2026-08-20T17:30:19Z and retrieved with `devicectl device copy from --domain-type appGroupDataContainer`.
- **The shield's own diagnostic entry was absent at that point.** Whether the extension never ran, or ran and lost its write before exiting, is not yet distinguished — the write is now flushed explicitly to remove that ambiguity, and the next device run settles it.

## Ruled out

- **Leftover state from the other variant.** The app group container was shared with `ios-pause-app-claude` and held its keys (`spikeLog`, `expectedEnd.interval16`, `shieldTapCount`, `targetScheme`). Deleting Pause destroyed the container; the symptom survived a clean install and re-add.
- **A second Pause installed.** Only `com.koubalabs.pause` is present.
- **Missing state files.** `devicectl` exposes only standard subdirectories, never the container root, so its listing is silent about `configuration.json` and the runtime files either way. Absence there is not evidence.

## Next

Read `shield-diagnostic-v1` from shared preferences after a device run:

```bash
xcrun devicectl device copy from --device <udid> \
  --domain-type appGroupDataContainer --domain-identifier group.com.koubalabs.pause \
  --source Library/Preferences/group.com.koubalabs.pause.plist --destination ./g.plist
plutil -extract "shield-diagnostic-v1" raw -o - g.plist
```

An entry names the failing stage. A second absence, now that the write is flushed, means the extension is not being invoked, and the question becomes why iOS is not asking it — cached configuration being the first candidate.

## Method note

Three conclusions were drawn and withdrawn during this investigation: that the repair variant's button was inert, that the state files were missing, and that the extension had never run. Each came from treating a tool's output as fact without first establishing what that tool reports. `log collect` needs USB and root; `devicectl` hides container-root files; shared preferences do not flush on process exit. Establish what an instrument measures before reading meaning into its silence.
