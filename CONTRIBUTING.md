# Contributing to AutoHush

Thanks for wanting to help. Every change is reviewed before it's merged, so
it helps to follow these few rules. Everyone taking part follows the
[code of conduct](CODE_OF_CONDUCT.md).

## Reporting a problem or an idea

[Open an issue](https://github.com/hfustercabre/AutoHush/issues/new/choose)
with its form: a bug report (with Diagnostics' report: Settings →
Diagnostics → Copy Report, and its logs: Show Logs… → Copy Logs), a
feature request, a player to support (when **Add an App…** found no way to
control it, with its check's log, which leaves out your Mac account's name
and what was playing) or a translation fix. A security problem goes
privately, as [SECURITY.md](SECURITY.md) says.

## Branches

- **`main`** holds the latest release. It only moves when a new version is
  published.
- **`stg`** (staging) is what the next release will be: `dev`'s changes,
  built and tested together. Releases, and release candidates for testing,
  are made from it.
- **`dev`** is where development happens. Every change goes there first,
  then to `stg`, then to `main`.
- Every other branch follows [Conventional Branch](https://conventionalbranch.org/):
  `<type>/<description>`, the description in lowercase letters and numbers
  joined by single hyphens (dots only in versions). The types are
  **`feature/`**, **`fix/`** and **`chore/`**, which anyone may use, and
  **`release/`** (preparing a release, `release/v1.1.0`) and **`hotfix/`**
  (an urgent fix to the latest release), which only the maintainer uses.

## Proposing a change

1. Fork the repository.
2. Create a branch from `dev` whose name says what it is:
   - **`feature/`** for something new, or a change to how something works
     (`feature/web-app-search`, `feature/longer-fades`);
   - **`fix/`** for a bug fix (`fix/resume-after-call`);
   - **`chore/`** for anything that doesn't change what AutoHush does:
     docs, translations, tests, tooling (`chore/update-readme`).
3. Check that it builds and its tests pass (DEVELOPMENT.md →
   [Build and test](DEVELOPMENT.md#build-and-test)), and that it follows the
   [style guide](STYLE_GUIDE.md). A change to what AutoHush does updates
   its flowcharts in [WORKFLOWS.md](WORKFLOWS.md) too.
4. Open a pull request into **`dev`**, not `main`, saying what it changes
   and why (its template asks for that, and how you checked it).

A check on every pull request flags one whose branch name or target doesn't
follow these rules; a wrong target can be fixed by editing the pull
request. The build with warnings as errors and the tests, on Xcode 27, run
once a change reaches `stg`, not on the pull request: check yours before
opening it. I review each pull request before approving and merging it, and
it reaches `main` with the next release. By opening one, you agree that your
contribution is licensed under the project's license, the GNU GPL version 3
or later (GPL-3.0-or-later).

## Where to look

- **How AutoHush works and where things go:**
  [DEVELOPMENT.md](DEVELOPMENT.md), including what adding a media
  player takes.
- **How it looks and reads:** [STYLE_GUIDE.md](STYLE_GUIDE.md).
- **What it does, step by step:** [WORKFLOWS.md](WORKFLOWS.md), flowcharts
  GitHub draws from their Mermaid source.
- **Text people read:** written as `String(localized:)` with a comment for
  translators (DEVELOPMENT.md → [Translations](DEVELOPMENT.md#translations)).
