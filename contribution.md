# Contributing to Behavio Context

Focused bug fixes, tests, accessibility improvements, and measurable context-size optimizations are welcome.

Before opening a pull request, run:

```sh
./script/test_core.sh
./script/check_native_only.sh
```

If full Xcode is installed, also run `./script/test_unit.sh` and `./script/test_integration.sh`.

Do not add telemetry, cloud speech fallbacks, keyboard logging, or full-display capture without an explicit privacy and product review.
