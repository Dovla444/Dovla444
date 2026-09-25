# Phase 0: Spike report

Status: **code done, waiting for device results.** The open questions can only be answered on your iPhone/iPad, so this report has two parts: what is already settled, and a test protocol whose results table you fill in.

> Honest caveat: the code was written in a Linux container without Xcode or a Swift toolchain. GitHub downloads were blocked there as well. **None of the Swift code has been compiled yet.** Expect a few compile errors on the first build. Paste them to me and I'll fix them. The libgit2 behaviour described below *was* verified, using libgit2 1.9.7 through its Python binding.

## 1. libgit2 package choice

| Candidate | libgit2 | Shape | Activity | Verdict |
|---|---|---|---|---|
| **[ibrahimcetin/libgit2](https://github.com/ibrahimcetin/libgit2)** tag `1.9.2` | 1.9.2 | SwiftPM **source** build (C target), TLS via system SecureTransport, SHA via CommonCrypto, no OpenSSL | Upstream fork with an added `Package.swift`. Used by [SwiftGitX](https://github.com/ibrahimcetin/SwiftGitX) (240 commits, 14 releases) | **Chosen** |
| [bdewey/static-libgit2](https://github.com/bdewey/static-libgit2) | 1.3.0 | binary XCFramework + OpenSSL 3.0.0 + libssh2 | 9 commits, stale | Rejected: libgit2 is 6 minor versions behind and bundles an old OpenSSL |
| [light-tech/Clibgit2](https://github.com/light-tech/Clibgit2) ([build scripts](https://github.com/light-tech/LibGit2-On-iOS)) | unclear | binary XCFramework + OpenSSL + libssh2 | 2 commits in the package repo | Rejected: version not stated, very thin maintenance |
| [mfcollins3/libgit2-apple](https://github.com/mfcollins3/libgit2-apple) | 1.5.0 | you build the XCFramework yourself (OpenSSL + libssh2 built separately) | 5 commits | Rejected: effectively "build it yourself" with extra steps |
| SwiftGitX | 1.9.2 | high-level wrapper over the chosen package | active | Not used directly. The spec asks for our own thin wrapper, and SwiftGitX would be a second dependency |
| SwiftGit2 | old | | unmaintained | Excluded by the spec |

**Why a source package instead of a binary XCFramework (deviation from "prefer binary"):** I found no maintained binary XCFramework with a current libgit2. A source build is also reproducible and needs no opaque binary or OpenSSL. It covers device and arm64 simulator automatically, and it pins an exact tag (`exact: "1.9.2"`).

Trade-offs:
- First clean build is slower, roughly 1–2 minutes to compile libgit2. Later builds are cached.
- HTTPS goes through **SecureTransport**. Apple has deprecated it, but it still ships in iOS 18/26 and GitHub accepts its TLS 1.2. If iOS removes it, the fallback is a fork of the package that switches to mbedTLS.
- The package defines `GIT_SSH_EXEC` on iOS. We never use SSH. If that part fails to compile for iOS, the fix is a 1-line fork. I haven't been able to check this.

## 2. Verified here (libgit2 1.9.7, local test)

| Assumption | Result |
|---|---|
| Git directory outside the vault | ✅ Init the git dir as *bare* in the container, then call `git_repository_set_workdir(repo, vault, 0)`. Index, status and checkout all work, and **no `.git` file or folder appears in the vault**. |
| Reopening | ⚠️ The git dir keeps `core.bare = true`, so `set_workdir` must be called on **every** open. `GitRepository.init` always does this. |
| First checkout into a non-empty folder | ✅ With `SAFE \| ALLOW_CONFLICTS`, existing vault files are **never overwritten** and are reported instead. Unrelated local files stay untouched. |
| Identical files on first sync | ⚠️ libgit2 reports a file that already exists **with identical content** as a conflict too, and leaves it out of the index. Phase 1 therefore needs its own "same content hash → just stage it" step. The spec requires this anyway. Nothing is lost either way. |

The same three checks are in `SyncKit/Tests/SyncKitTests/GitRepositoryTests.swift`. They run with `cd SyncKit && swift test` on your Mac and need no network.

## 3. Decisions and trade-offs (one line each)

- **Folder picker:** uses SwiftUI `.fileImporter(allowedContentTypes: [.folder])`. It is the same system `UIDocumentPickerViewController` in open mode and returns the same security-scoped URL, without a UIKit wrapper. It's simpler, and the result is identical.
- **Bookmark:** `bookmarkData(options: [])`, because iOS has no `.withSecurityScope`. It is stored in the App Group and re-saved when stale. If resolution fails, nothing is touched.
- **Data protection:** container files use `completeUntilFirstUserAuthentication`. They are readable while locked, but only after the first unlock since boot. This is required for background sync. It is weaker than `complete`, and the token in the Keychain has the same class.
- **Keychain group:** `$(AppIdentifierPrefix)<prefix>.tide.shared`, injected into Info.plist, so the app and extension use the identical string.
- **Intents in both targets:** the intent sources live in `Shared/`, compiled into the app and the widget extension. Every run logs the bundle ID of the process that executed it, which answers "where do widget intents run" empirically.
- **Project file:** Xcode 16+ synchronized folders (`objectVersion 77`), so adding a file never touches `project.pbxproj`.

## 4. Build on your Mac

1. Edit **`Config/Signing.xcconfig`**: `DEVELOPMENT_TEAM` and `TIDE_BUNDLE_PREFIX`. That's the only place.
2. Open `Tide.xcodeproj` in Xcode 26. SwiftPM resolves libgit2 on its own.
3. Signing is automatic, so Xcode registers the App Group `group.<prefix>.tide` and the Keychain group. If it complains, open *Signing & Capabilities* for both targets once.
4. Run the **Tide** scheme on your iPhone.

If Xcode doesn't pick up the local `SyncKit` package: *File → Add Package Dependencies… → Add Local… → SyncKit*, then add the `SyncKit` library to both targets under *Frameworks*.

## 5. Device test protocol

Preparation:
- In Tide Spike, **Choose Folder…** → On My iPhone › Obsidian › *a test vault* (not your real one for T7).
- Paste a fine-grained token (only the vault repo, *Contents: Read and write*) → **Save and Check Token** → pick the repository.
- Add the **Tide Spike** widget to the Home Screen (small) and to the Lock Screen (circular).
- In Shortcuts → Automation, create:
  - *App → Obsidian → Is Opened*, **Run Immediately** → action *Append Test Line* (Trigger: `automation open`)
  - *Charger → Is Connected*, **Run Immediately** → *Append Test Line* (Trigger: `automation locked`). This is the easiest way to fire an automation while the phone is locked.

Every run appears in the app's **Log** section with its process, lock state and duration. `Tide-Spike.md` in the vault gets one line per successful write.

| # | Test | How | Result (process · locked? · outcome · seconds) |
|---|---|---|---|
| T1 | Append from the app | Tap **Append Test Line** | |
| T2 | Append from automation, unlocked | Open Obsidian | |
| T3 | Append from automation, **locked** | Lock phone, wait 1 min, plug in charger | |
| T4 | Append from Home Screen widget | Tap the first widget button | |
| T5 | Append from Lock Screen widget | Tap the circular widget while locked | |
| T6 | Bookmark after reboot | Reboot, unlock, run T1. Also: reboot, **don't unlock**, plug charger (T3) | |
| T7 | Clone time | Point the folder at an **empty** folder, then **Clone Into Container** with your real repo. Note objects, MB, seconds and file count | |
| T8 | Fetch from widget (memory limit, Keychain from extension) | Tap the second widget button | |
| T9a | Runtime from Shortcuts, foreground | Run *Measure Runtime* (600 s) in the Shortcuts app and keep it open | |
| T9b | Runtime from Shortcuts, backgrounded | Start it, switch to another app | |
| T9c | Runtime from automation, locked | Charger automation → *Measure Runtime*, lock, wait 10 min | |

The app's *Background runtime* section shows the last measurement. If it says "killed by iOS", the time shown is how long iOS allowed the run.

## 6. Go / no-go

**libgit2 is a GO** if T7 clones your vault successfully and T2/T3 or T8 can fetch from an intent.

It becomes a **NO-GO**, and I'd ask you before switching to the GitHub Git Data API fallback, if any of these happen:
- the package can't be made to build for iOS with a small patch
- TLS to github.com fails through SecureTransport
- libgit2 crashes or exceeds memory in both the app-process intent and the widget extension

Things these results decide for Phase 1+:
- **T3/T5/T6:** whether locked-device sync can touch the vault at all. Obsidian's files carry *Obsidian's* data protection class, not ours. If they are unreadable while locked, sync will skip the locked case and catch up on unlock.
- **T4/T8 process:** if widget intents run in the extension, the lock file, bookmark and Keychain must all work there. If extension memory is too tight for libgit2, the widget will ask the app process to sync instead of syncing itself.
- **T9:** how much work one run may do before it has to be resumable. This drives batch sizes in Phase 1.

## 7. Unverified APIs (checked from docs and memory, not from a compiler)

- `TimelineProvider` completion signatures under Swift 6 (possible `@Sendable` mismatch).
- `static let description = IntentDescription(…)` under strict concurrency.
- `$(AppIdentifierPrefix)` expansion inside Info.plist. If the Keychain save fails with `-34018`, this is the cause.
- The hand-written `project.pbxproj` (it parses, and all references are consistent).
- libgit2 C types seen from Swift, e.g. `git_checkout_strategy_t.rawValue` as `UInt32`, callback closures converting to C function pointers.
