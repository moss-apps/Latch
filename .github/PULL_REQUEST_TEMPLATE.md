## Summary

<!-- What changed and why. Link an issue or roadmap item if relevant. -->

## Related issue

<!-- Closes #… or "none". -->

## Checklist

- [ ] `dart format --output=none --set-exit-if-changed lib test` passes
- [ ] `flutter analyze` passes
- [ ] `flutter test` passes
- [ ] `make latchd-test` passes (if `latchd/` or `pocketbase/` changed)
- [ ] `CHANGELOG.md` updated under the current version heading
- [ ] Docs updated if behavior, setup, or scope changed (`docs/` is the source of truth)
- [ ] No secrets, keys, keystores, or machine-local files committed
- [ ] No invariant violated (see `CONTRIBUTING.md`)
