# Build guide

Generated output stays under `build/`, `dist/`, and `tdlib/`. The TDLib source checkout and native build directories are ignored by Git.

## Prerequisites

- Go 1.27 or newer
- Git, CMake 3.20 or newer, and a C/C++ compiler
- Fyne CLI: `go install fyne.io/fyne/v2/cmd/fyne@latest`

Run `make setup` to check common tools and tidy the Go module.

TDLib is tracked as a Git submodule at `tdlib/src`, pinned by the gitlink in the parent repository. For a fresh checkout, initialize it with `make submodules` or `git submodule update --init --recursive`.

## Run

Run the desktop application natively on macOS with the macOS TDLib build:

```sh
make run
# equivalent: make run macos
```

For an Android phone or emulator, set the application ID and run:

```sh
APP_ID=com.example.telety make run android
# alias: APP_ID=com.example.telety make run phone
```

The Android command builds the Android-specific TDLib `.so`, packages it into the APK, installs the APK with `adb`, and launches it using the same `APP_ID`. Use `ANDROID_SERIAL=<device-id>` when more than one device is connected. Android SDK, NDK, Java, `adb`, and a connected device/emulator are required.

## macOS

Install Xcode Command Line Tools and CMake, then run:

```sh
make build macos
# or: make build TARGET=macos
```

TDLib uses the current `uname -m` architecture. Override it with `MACOS_ARCH=amd64` or `MACOS_ARCH=arm64` when the matching compiler/toolchain is available. The app is written to `dist/macos/`.

## Android

Install Android SDK platform/build tools and an NDK with its CMake toolchain. Set `ANDROID_HOME` or `ANDROID_SDK_ROOT`; the newest installed NDK is selected automatically. Set `ANDROID_NDK` to select a specific one.

```sh
make build android
# or: make build TARGET=android
```

The default ABI is `arm64-v8a` and can be changed with `ANDROID_ABI`. TDLib is built with the Android CMake toolchain, and Fyne packages its `.so` into `dist/android/Telety.apk`.

## Web

```sh
make build web
# or: make build TARGET=web
```

The WebAssembly build never configures or links native TDLib. `internal/telegram` supplies a web implementation that can later connect to a remote Telegram backend. Assets are written to `dist/web/`.

Run the web application locally with:

```sh
make run web
# or: WEB_PORT=9000 make run web
```

This builds the web artifacts and starts a Python HTTP server. Open `http://127.0.0.1:8080/wasm/` in a browser. `WEB_HOST` and `WEB_PORT` are configurable.

The web target also builds TDLib itself with Emscripten using TDLib's official `td_wasm` target. The build automatically downloads and caches OpenSSL 1.1.1w under `tdlib/openssl/` because TDLib v1.8.0 requires a crypto library for WebAssembly. The generated `td_wasm.js` and `td_wasm.wasm` files are copied to `dist/web/tdlib/`. Go WebAssembly cannot use CGo directly, so the TDLib module is exposed as a separate JavaScript/WASM asset for a future JS bridge; it is not linked into the Fyne Go binary.

To build only this library:

```sh
make tdlib-web
```

Emscripten must be installed and activated so `emcmake`, `emmake`, and `emcc` are available. Automatic OpenSSL preparation requires `curl`, `tar`, `make`, and `perl`. To use an existing wasm OpenSSL prefix instead, set `EMSCRIPTEN_OPENSSL_ROOT`:

```sh
EMSCRIPTEN_OPENSSL_ROOT=$HOME/opt/openssl-wasm make tdlib-web
```

The build fails early with an actionable error when this dependency is missing. A native macOS OpenSSL library cannot be used for this target.

## TDLib version and cache

The default TDLib version is `v1.8.0`. Pin another tag or commit without editing files:

```sh
TDLIB_VERSION=v1.8.0 make build macos
```

The TDLib targets initialize the official repository submodule, configure CMake, build `tdjson`, and install it below `tdlib/install/<platform>/`. The submodule commit pins the source revision; `TDLIB_VERSION` can select another tag or commit for a local build. A fingerprint containing the revision, target, architecture, NDK, ABI, and API level is stored in the target build directory; matching builds are reused.

## Troubleshooting

- `Android SDK not found`: set `ANDROID_HOME` or `ANDROID_SDK_ROOT` to the SDK directory.
- `Android NDK not found`: install an NDK and set `ANDROID_NDK` to its directory.
- `Fyne CLI was not found`: run `go install fyne.io/fyne/v2/cmd/fyne@latest`, then add `$(go env GOPATH)/bin` to `PATH`.
- CMake cannot find a compiler: install Xcode Command Line Tools on macOS or the NDK toolchain for Android.
- `make clean-tdlib` removes only native caches; `make clean` also removes application output.