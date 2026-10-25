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

- [scrctl](https://github.com/scrctl/scrctl)
- [XDeviceBridge](https://github.com/scrctl/XDeviceBridge)
