# Contributing to AutoHush

Thanks for wanting to help. Every change is reviewed before it's merged, so
it helps to follow these few rules.

## Reporting a problem or an idea

[Open an issue](https://github.com/hfustercabre/AutoHush/issues/new/choose)
with its form: a bug report (with Diagnostics' report: Settings →
Diagnostics → Copy Report), a feature request, a player to support (with
[Player Check](Tools/PlayerCheckApp)'s report) or a translation fix. A
security problem goes privately, as [SECURITY.md](SECURITY.md) says.

## Branches

- **`main`** holds the latest release. It only moves when a new version is
  published.
- **`wip`** is where development happens. Every change goes there first.

## Proposing a change

1. Fork the repository.
2. Create a branch from `wip` whose name starts with what it is:
   - **`fix-`** for a bug fix (`fix-vlc-resume`);
   - **`feature-`** for something new (`feature-qobuz`);
   - **`change-`** for a change to how something already works
     (`change-fade-length`).
3. Check that it builds and its tests pass (README →
   [Build and test](README.md#build-and-test)), and that it follows the
   [style guide](STYLE_GUIDE.md).
4. Open a pull request into **`wip`**, not `main`, saying what it changes
   and why (its template asks for that, and how you checked it).

A check on every pull request flags one whose branch name or target doesn't
follow these rules; a wrong target can be fixed by editing the pull
request. I review each pull request before approving and merging it, and it
reaches `main` with the next release.

## Where to look

- **How AutoHush works and where things go:** README →
  [For developers](README.md#for-developers), including what adding a media
  player takes.
- **How it looks and reads:** [STYLE_GUIDE.md](STYLE_GUIDE.md).
- **Text people read:** written as `String(localized:)` with a comment for
  translators (README → [Translations](README.md#translations)).
