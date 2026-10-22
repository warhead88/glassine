# Contributing to Glassine

Thanks for wanting to help. Bug reports, ideas and pull requests are all welcome.

## Reporting bugs

Open an issue with your macOS version, what you did, what you expected and what happened.
Logs help: `/usr/bin/log stream --predicate 'subsystem == "com.warhead88.glassine"'` while you reproduce it.

## Building

You need Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
scripts/install.sh     # build and install to /Applications
scripts/test.sh        # unit tests
```

Out of the box Glassine is signed ad hoc. That works, but macOS asks for Screen Recording again
after every rebuild, because the permission belongs to the app's signature. To keep it, copy
`Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig` (it isn't committed) and
set your Apple ID's team — a free Personal Team is enough — or a self-signed certificate.

## Pull requests

- One change per pull request, with a short description of what and why.
- Match the surrounding code: naming, comment density, features in their own folder under `Glassine/`.
- Keep logic that can be tested in pure functions (see `Glassine/Core/Geometry.swift`) and add tests;
  run `scripts/test.sh` before you push.
- Add a line under `## [Unreleased]` in `CHANGELOG.md` for anything users notice, written for them —
  it is what the update window shows.
- New features get a checklist entry in `TESTING.md`.

## License of contributions

Glassine is licensed under the GNU GPL v3, and so is your contribution. In addition, by submitting a
pull request you agree that warhead88 may also distribute your contribution as part of Glassine under
other terms — for example in a Mac App Store build, whose terms don't fit the GPL — and you confirm
that you wrote it or have the right to submit it. You keep the copyright to your work.

The name Glassine and its icon are not part of the license (see README → License).
