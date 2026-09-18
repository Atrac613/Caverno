# Embedded Python (run_python_script)

The `run_python_script` tool runs against a vendored, pure-Python worker bundled
as `assets/python/app.zip`, executed by a `serious_python` interpreter staged
into the platform build. `CLAUDE.md` keeps the repack command; everything else
lives here.

```bash
# Repack the worker asset after editing
# lib/core/services/script_runtime/worker/ or its vendored __pypackages__/.
# Produces a deterministic assets/python/app.zip.
python3 tool/pack_python_worker.py

# Vendor another package (mobile supports pure-Python wheels only), then repack:
python3 -m pip install --no-deps --no-compile \
  --target lib/core/services/script_runtime/worker/__pypackages__ <package>

# One-time-per-machine native setup for serious_python, after `flutter pub get`.
# Stages the interpreter (Python.xcframework + compiled stdlib) into
# dist_{ios,macos}/{xcframeworks,stdlib} and the Android site dirs. `pod
# install` runs the same staging via the podspec's prepare_command, so this
# mostly pre-stages and validates. It prints a benign
# "cp: .../iphoneos.arm64/*: No such file" / "total size is 0" while syncing
# the empty pure-Python site-packages.
tool/prepare_serious_python.sh

# iOS/macOS are then ready. Android ALSO needs this at build time, because the
# gradle plugin reads it live:
export SERIOUS_PYTHON_SITE_PACKAGES="$(pwd)/build/serious_python_site"

# Worker regression suite (system python3, no Flutter):
python3 test/python/worker_test.py

# On-device integration test that proves the native run_python_script path:
flutter test integration_test/python_runtime_test.dart -d <device-id>
```
