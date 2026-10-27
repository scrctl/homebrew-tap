# scrctl Homebrew tap

```sh
brew install scrctl/tap/scrctl
# Or install the device bridge alone:
brew install scrctl/tap/xdb
```

`scrctl` automatically installs `xdb`. The desktop frontend and device server are
separate processes. xdb starts on demand; no login service is installed.
DDI images are downloaded on demand and pairing records stay in the user data
directory, outside Homebrew's Cellar.

Both formulae build pinned release sources. Pull-request CI builds and tests
bottles on macOS 15 ARM64 and Linux x86-64; compatible bottles are used when
available. Other supported hosts build from source. Homebrew bottles are separate
builds from the Developer ID notarized ZIPs on the upstream release pages.

Maintainers: put formula changes in a PR. Once its checks pass, run the `brew
pr-pull` workflow with the PR number and exact reviewed head SHA to publish bottles
and merge the formula changes. No scheduled version bumps are enabled.

## Update xdb in one command

In a clean working clone of this tap, with Python 3.10+, Git, curl and an
authenticated `gh` CLI:

```sh
gh auth status
python3 tools/update_xdb.py 1.2.0 --dry-run
python3 tools/update_xdb.py 1.2.0
```

Replace `1.2.0` with an already published stable xdb release. The tool resolves
its tag commit, downloads the HTTPS source archive, checks its embedded commit
marker and CMake version, and computes the formula SHA256. It starts from fetched
`origin/main`, removes old bottle metadata, commits/pushes `codex/xdb-<version>`
and creates a PR. Existing open PRs are reused; already-current versions retain
their bottles. Downgrades, changed same-version hashes, dirty worktrees and
colliding branches require manual review; branches are never force-pushed.

`--dry-run` fetches metadata/sources and previews the diff without editing files,
switching branches, committing or opening a PR. A successful update leaves you on
the prepared branch. If publishing the branch/PR fails, inspect that branch
before retrying. The tool uses your `gh` login so PR CI runs normally; it does not
add cross-repository tokens or automatically merge/publish bottles. After CI
passes, continue with the existing `brew pr-pull` workflow and exact head SHA.
The new PR's head SHA is printed for that review step. Dependency/resource changes
still need PR review. Only the xdb formula is updated; scrctl has a separate
release/client-source pin.

- [scrctl](https://github.com/scrctl/scrctl)
- [XDeviceBridge](https://github.com/scrctl/XDeviceBridge)
