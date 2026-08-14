# Verifying on managed hardware

For a real Jamf-managed Apple TV running an App Store install of **AutoStreamDisplay**
(`edu.princeton.autostreamdisplay`), 1.1.

## Why this run matters

Three claims have never been observed anywhere — not in the simulator, not in CI, not
under review. Everything else in this document is regression checking; these three are
the reason to do it at all.

| Claim | Status | Why it could not be tested before |
|---|---|---|
| **Declarative reconcile** — the app follows a payload edited while it runs | unverified | needs a genuine MDM write. `defaults import` is clobbered by the app's own write-back, so it cannot stand in |
| **Recovery round trip** — a frozen stream observed coming back unaided | unverified, [#9](https://github.com/pubino/AutoSignDisplay/issues/9) | simulator networking never demonstrably restored; the spinner persisted every attempt |
| **PIN entry announces itself** to VoiceOver | unverified | VoiceOver does not run in the tvOS simulator |

A green result on the first two is the substance of 1.1. Record what actually happens on
#9 either way — a reproducible failure on hardware is more valuable than the current
silence.

## Setup

1. **Apps and Books → AutoStreamDisplay** — 50 licences allocated to this Jamf instance.
2. **Jamf Pro → Devices → Mobile Device Apps → AutoStreamDisplay**
   - *Scope* — the test devices only.
   - *App Configuration* — paste [`../mdm/jamf-app-config-verify.xml`](../mdm/jamf-app-config-verify.xml).
     Deliberately not a kiosk payload: `SettingsDisabled`, `ViewOnlyMode` and
     `SettingsPIN` are absent so the UI can be walked and the locks tested separately.
3. Confirm the install reports 1.1, not a TestFlight build. A device that already carries
   a TestFlight copy of `edu.princeton.autosigndisplay` is a *different app* and will sit
   alongside this one — check which icon you are opening.

## Reading the log

The log subsystem is **derived from the bundle identifier**, so on this build it is
`edu.princeton.autostreamdisplay` — not the private app's.

1. Pair the Apple TV: **Xcode → Window → Devices and Simulators**, select the device,
   enter the pairing code shown on the TV.
2. **Console.app** → the device in the sidebar → filter *Subsystem* on
   `edu.princeton.autostreamdisplay`.
3. **Action → Include Debug Messages.** Debug-level entries are not persisted to the log
   store, so they exist only in a live stream. If you go looking for them after the fact
   they will not be there.

Every check below is designed to be readable from across the room without this. The log
is for when a check fails.

---

## 1. The payload arrives

**Pass:** heading reads `MDM VERIFY — Sherrerd Hall`; Stream Presets shows exactly
*Verify Scenic* and *Verify Announcements*; playback starts unaided; Settings → Recovery
shows Retry Timeout **7s**.

The 7 is the load-bearing check — it is not one of the six values the UI offers
(3, 5, 10, 15, 30, 60), so it cannot have come from a local default.

**If the heading shows `AutoStreamDisplay`** the payload did not arrive: the app fell back
to `CFBundleDisplayName`. That is Jamf-side — scope, or config not saved.

## 2. Declarative reconcile — the 1.1 feature

Leave the app **playing**. Do not force-quit at any point; doing so proves only that
launch reads the payload, which 1.0 already did.

1. In Jamf, change `DisplayTitle` to `MDM VERIFY — reconciled`. Save, push.
2. Watch the screen. **Pass:** the heading changes with no interaction and no relaunch.

Expect it within about **RetryTimeout + 1.5s** — ~9s with the 7s in this payload — plus
Jamf's push latency, which dominates and is the unpredictable part.

Then the stronger case:

3. Change `DefaultChannel` to the Announcements URL. **Pass:** the playing channel
   switches on its own.

**Precondition that matters:** the poll rides the playback watchdog's tick, which runs
whenever a player exists and the app is foregrounded — including while sitting on the
channel list — but **not** after someone has pressed Stop. Verify from a playing state,
which is the only state a kiosk is ever in.

**If nothing happens,** capture the log before force-quitting. Absence of
`Managed configuration changed — reconciling` means the payload never reached the app's
defaults; presence of it with no visible change means reconcile ran but application
failed. Those are different bugs and the log is the only way to tell them apart.

## 3. A payload overwrites local edits

`SettingsDisabled` is absent here, so the fields are editable — this is the only window
in which the stomp is observable.

1. On the device, type a junk `Stream URL` in Settings and leave it there.
2. Push any payload change.

**Pass:** the pushed values win. Deliberate — the payload is desired state.

## 4. Recovery round trip — [#9](https://github.com/pubino/AutoSignDisplay/issues/9)

The one that has never worked in front of me. Confirm `Auto Resume` is on first.

1. Start playback, let it run.
2. Kill the network at the device — unplug Ethernet, or drop Wi-Fi in tvOS Settings.
   **Leave it down for at least 60 seconds**, well past the 7s retry timeout.
3. Restore the network. **Touch nothing.**

**Pass:** playback resumes unaided within a few retry intervals.

**Record precisely, whichever way it goes:** how long the network was down, how long until
recovery or how long you waited, and what was on screen — frozen last frame, spinner, or
black. Attach the log across the whole window. The simulator failed here three times with
a spinner that never cleared, and it was never settled whether that was the app or
simulator networking that never truly came back. Hardware is the deciding test.

Note the log line `Auto-resuming stream (no player item)` fires on one specific path.
Recovery from a *stalled* item goes through the stall branch instead — do not read its
absence as nothing having happened.

## 5. The kiosk lockdown

Swap the App Configuration to [`../mdm/jamf-app-config-kiosk.xml`](../mdm/jamf-app-config-kiosk.xml).

**Pass:** Settings and Manage Presets refuse edits; the preset list cannot be changed;
`ViewOnlyMode` hides what it should. The lock is `settingsDisabled` /
`channelPresetsManaged` — the guards that exist specifically to protect the managed path.

## 6. PIN entry announces itself (VoiceOver)

Needs hardware; this is the one accessibility finding the Accessibility Inspector could
not cover.

Enable VoiceOver (**Settings → Accessibility**, or triple-press TV), then reach the PIN
prompt with `SettingsPIN` set.

**Pass, by ear:** the prompt is announced on appearance, wrong entries are announced as
failures, and digits entered are not spoken individually in a way that leaks the PIN
aloud. The other four findings were verified with the Inspector; only this one depends on
hearing it.

## 7. Payload removal resets sticky state

Unscope the App Configuration — do not uninstall the app.

**Pass:** presets return to the built-in default, which on this build is the single
*Featured Event Stream*, and the managed locks lift. Removal is a reconcile like any
other; a display left on an administrator's locked channel list after the payload was
pulled would be stranded.

---

## Recording the result

Whatever happens, #9 should end this run either closed against an observation or updated
with a hardware reproduction. It has been the outstanding unknown since 1.1 was designed,
and it is the only item here where a negative result is genuinely useful.
