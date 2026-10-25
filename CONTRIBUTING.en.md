[Русский](CONTRIBUTING.md) | **English**

# Contributing

See [status](Docs/STATUS.en.md) and [build instructions](Docs/BUILDING.en.md). In bug reports, include the Koto/macOS versions, architecture, engine, minimal steps and expected behavior. Use synthetic phrases; never publish keys or private screenshots/text. Reports and proposals are welcome in Russian or English.

Keep each change focused on one task with appropriate checks. Preserve Swift 6 strict concurrency, cancellation/stale-response protection, privacy gates and the exclusion of weights from Git. Comments should explain why decisions were made. Tests must not remove system languages or automatically download a large model.

Before a substantial code contribution, agree on distribution terms with the owner. Do not include third-party code without the appropriate terms; retain third-party notices.

## License and community

First-party contributions are submitted under the repository's [MIT license](LICENSE), unless another arrangement is explicitly agreed before submission. Preserve Copyright (c) 2026 Slipcast-Dev and third-party notices. Follow the [Code of Conduct](CODE_OF_CONDUCT.md).

Before submitting, run `bash script/test_swift_ci.sh` and `swiftlint lint --strict --config .swiftlint.yml`. Dependabot submodule updates must also update the reviewed commit and SHA-256 source locks; do not merge an unverified runtime revision.
