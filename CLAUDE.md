# System Controller: project rules

## Branches and releases

- `main` is the only release branch. Every release is tagged on `main` (`vX.Y.Z`) and built from there.
- New work starts on its own branch from `main`: `feat/<name>`, `fix/<name>`.
- A feature branch is tried on this Mac first: `scripts/build-app.sh --install`, then use it for real.
  It is merged into `main` only after it works there and `swift test` passes.
- Release: merge into `main` → tag → `VERSION=X.Y.Z scripts/build-app.sh --universal --dmg` →
  `gh release create vX.Y.Z build/SystemController-X.Y.Z.{dmg,zip,sha256}`.
- Release files are named `SystemController-<version>.*`. `install.sh` downloads by that name
  (and falls back to the old `SoundControl-<version>.*` for releases up to 1.2.0).

## Memory

The app sits in the menu bar all day, so RAM counts. Idle footprint is about 32 MB; keep it there.

- Loops that read files or parse JSON with Foundation run each chunk inside `autoreleasepool`.
  Off the main thread (actors, `Task.detached`) nothing drains the pool until the call ends;
  `ClaudeUsageScanner` peaked at 340 MB on 427 MB of transcripts without it, 16 MB with it.
- Read big files in bounded chunks or tails, never whole.
- Do not write an `@Observable` property when the value did not change: every write redraws its readers.
- Work that only feeds a view runs while that view is on screen (`beginWatching` / `endWatching`).
- Check with `footprint <pid>` (current and peak) after changes that touch polling or file reading.
