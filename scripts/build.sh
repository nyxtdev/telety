#!/bin/sh
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GO=${GO:-go}
CMAKE=${CMAKE:-cmake}
TDLIB_VERSION=${TDLIB_VERSION:-v1.8.0}
WEB_OPENSSL_VERSION=${WEB_OPENSSL_VERSION:-1.1.1w}
ANDROID_ABI=${ANDROID_ABI:-arm64-v8a}
ANDROID_API=${ANDROID_API:-26}
APP_ID=${APP_ID:-com.example.telety}
APP_NAME=${APP_NAME:-Telety}
WEB_HOST=${WEB_HOST:-127.0.0.1}
WEB_PORT=${WEB_PORT:-8080}

TDLIB_ROOT=${TDLIB_ROOT:-$ROOT_DIR/tdlib}
TDLIB_SRC=${TDLIB_SRC:-$TDLIB_ROOT/src}
TDLIB_SUBMODULE_PATH=${TDLIB_SUBMODULE_PATH:-tdlib/src}
TDLIB_BUILD=${TDLIB_BUILD:-$TDLIB_ROOT/build}
TDLIB_INSTALL=${TDLIB_INSTALL:-$TDLIB_ROOT/install}
BUILD_ROOT=${BUILD_ROOT:-$ROOT_DIR/build}
DIST_ROOT=${DIST_ROOT:-$ROOT_DIR/dist}

die() { echo "Error: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' was not found. Install it and retry."; }

python_cmd() {
	if command -v python3 >/dev/null 2>&1; then
		echo python3
		return
	fi
	if command -v python >/dev/null 2>&1; then
		echo python
		return
	fi
	die "Python 3 was not found. Install Python 3 to run the web target."
}

android_sdk() {
	ANDROID_SDK=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
	[ -n "$ANDROID_SDK" ] || die "Android SDK not found. Set ANDROID_HOME or ANDROID_SDK_ROOT."
	[ -d "$ANDROID_SDK" ] || die "Android SDK directory does not exist: $ANDROID_SDK"
	export ANDROID_SDK_ROOT=$ANDROID_SDK
}

android_ndk() {
	android_sdk
	if [ -n "${ANDROID_NDK:-}" ]; then
		NDK=$ANDROID_NDK
	elif [ -n "${ANDROID_NDK_HOME:-}" ]; then
		NDK=$ANDROID_NDK_HOME
	else
		NDK=$(find "$ANDROID_SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n 1)
	fi
	[ -n "${NDK:-}" ] || die "Android NDK not found. Install an NDK and set ANDROID_NDK."
	[ -f "$NDK/build/cmake/android.toolchain.cmake" ] || die "Invalid Android NDK: missing CMake toolchain in $NDK"
	export ANDROID_NDK=$NDK
}

android_adb() {
	android_sdk
	if command -v adb >/dev/null 2>&1; then
		echo adb
		return
	fi
	if [ -x "$ANDROID_SDK_ROOT/platform-tools/adb" ]; then
		echo "$ANDROID_SDK_ROOT/platform-tools/adb"
		return
	fi
	die "Android adb not found. Install Android platform-tools and add them to PATH."
}

check_common() {
	need_cmd "$GO"
	need_cmd "$CMAKE"
	need_cmd git
}

check_emscripten() {
	need_cmd emcmake
	need_cmd emmake
	need_cmd emcc
	need_cmd em++
}

web_openssl_args() {
	root=${EMSCRIPTEN_OPENSSL_ROOT:-}
	crypto=${EMSCRIPTEN_OPENSSL_CRYPTO_LIBRARY:-}
	include=${EMSCRIPTEN_OPENSSL_INCLUDE_DIR:-}
	if [ -z "$root" ] && [ -z "$crypto" ]; then
		build_web_openssl
		root="$TDLIB_ROOT/openssl/install"
	fi
	if [ -n "$root" ]; then
		[ -f "$root/include/openssl/opensslv.h" ] || die "Invalid EMSCRIPTEN_OPENSSL_ROOT: missing include/openssl/opensslv.h"
		include=$root/include
		crypto=${crypto:-$root/lib/libcrypto.a}
	fi
	[ -n "$include" ] || die "Set EMSCRIPTEN_OPENSSL_ROOT or EMSCRIPTEN_OPENSSL_INCLUDE_DIR for the WebAssembly OpenSSL headers."
	[ -f "$include/openssl/opensslv.h" ] || die "Emscripten OpenSSL headers not found: $include/openssl/opensslv.h"
	[ -f "$crypto" ] || die "Emscripten OpenSSL crypto library not found: $crypto"
	OPENSSL_WEB_ARGS="-DOPENSSL_FOUND=TRUE -DOPENSSL_INCLUDE_DIR=$include -DOPENSSL_CRYPTO_LIBRARY=$crypto"
}

build_web_openssl() {
	install="$TDLIB_ROOT/openssl/install"
	if [ -f "$install/include/openssl/opensslv.h" ] && [ -f "$install/lib/libcrypto.a" ]; then
		echo "Emscripten OpenSSL is cached at $install"
		return
	fi
	need_cmd curl
	need_cmd tar
	need_cmd make
	need_cmd perl
	archive="$TDLIB_ROOT/openssl/openssl-$WEB_OPENSSL_VERSION.tar.gz"
	source="$TDLIB_ROOT/openssl/src/openssl-$WEB_OPENSSL_VERSION"
	mkdir -p "$TDLIB_ROOT/openssl"
	if [ ! -f "$archive" ]; then
		curl -fsSL "https://www.openssl.org/source/openssl-$WEB_OPENSSL_VERSION.tar.gz" -o "$archive"
	fi
	if [ ! -d "$source" ]; then
		mkdir -p "$TDLIB_ROOT/openssl/src"
		tar -xzf "$archive" -C "$TDLIB_ROOT/openssl/src"
	fi
	(
		cd "$source"
		CC=emcc AR=emar RANLIB=emranlib ./Configure linux-generic32 no-shared no-asm no-tests no-afalgeng no-capieng no-dso --prefix="$install"
		emmake make build_libs -j "${CMAKE_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
		emmake make install_sw
	)
}

ensure_source() {
	[ -f "$ROOT_DIR/.gitmodules" ] || die "TDLib submodule is not configured. Run: make submodules"
	git -C "$ROOT_DIR" submodule update --init -- "$TDLIB_SUBMODULE_PATH"
	[ -f "$TDLIB_SRC/.git" ] || die "TDLib submodule is missing at $TDLIB_SRC. Run: make submodules"
	git -C "$TDLIB_SRC" cat-file -e "$TDLIB_VERSION^{commit}" 2>/dev/null || \
		git -C "$TDLIB_SRC" fetch --tags origin "$TDLIB_VERSION"
	git -C "$TDLIB_SRC" checkout --quiet "$TDLIB_VERSION" || die "TDLib version '$TDLIB_VERSION' was not found in the submodule."
}

tdlib_build() {
	platform=$1
	check_common
	if [ "$platform" = web ]; then
		tdlib_build_web
		return
	fi
	if [ "$platform" = android ]; then
		android_ndk
	fi
	ensure_source

	config="$TDLIB_BUILD/$platform"
	install="$TDLIB_INSTALL/$platform"
	stamp="$config/.tdlib-build.stamp"
	if [ "$platform" = macos ] && [ -f "$config/CMakeCache.txt" ] && grep -q '^CMAKE_SYSTEM_NAME.*=Darwin$' "$config/CMakeCache.txt"; then
		rm -rf "$config"
	fi
	mkdir -p "$config" "$install"
	if [ "$platform" = macos ]; then
		arch=${MACOS_ARCH:-$(uname -m)}
		generator_args="-DCMAKE_OSX_ARCHITECTURES=$arch"
		platform_args=""
	else
		generator_args="-DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake -DANDROID_ABI=$ANDROID_ABI -DANDROID_PLATFORM=android-$ANDROID_API"
		platform_args="-DCMAKE_SYSTEM_NAME=Android"
		host_config="$TDLIB_BUILD/host-generation"
		"$CMAKE" -S "$TDLIB_SRC" -B "$host_config" -G "${CMAKE_GENERATOR:-Unix Makefiles}" \
			-DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
			-DTD_ENABLE_JNI=OFF -DTD_ENABLE_DOTNET=OFF -DTD_ENABLE_NATIVE=OFF
		"$CMAKE" --build "$host_config" --target prepare_cross_compiling --parallel "${CMAKE_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
	fi
	fingerprint=$(printf '%s\n' "$TDLIB_VERSION" "$platform" "${MACOS_ARCH:-}" "$ANDROID_ABI" "$ANDROID_API" "${ANDROID_NDK:-}" | shasum | awk '{print $1}')
	if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$fingerprint" ] && { [ -f "$install/lib/libtdjson.dylib" ] || [ -f "$install/lib/libtdjson.so" ]; }; then
		echo "TDLib ($platform) is cached at $install"
		return
	fi

	"$CMAKE" -S "$TDLIB_SRC" -B "$config" -G "${CMAKE_GENERATOR:-Unix Makefiles}" \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$install" \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DTD_ENABLE_JNI=OFF -DTD_ENABLE_DOTNET=OFF -DTD_ENABLE_NATIVE=OFF \
		$platform_args $generator_args
	if [ "$platform" = macos ]; then
		"$CMAKE" --build "$config" --target tdmime_auto --parallel "${CMAKE_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
	fi
	"$CMAKE" --build "$config" --target tdjson tdjson_static --parallel "${CMAKE_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
	"$CMAKE" --install "$config"
	if [ ! -f "$install/lib/libtdjson.dylib" ] && [ ! -f "$install/lib/libtdjson.so" ]; then
		die "TDLib built but libtdjson was not installed in $install/lib"
	fi
	printf '%s\n' "$fingerprint" > "$stamp"
}

tdlib_build_web() {
	check_emscripten
	web_openssl_args
	ensure_source

	config="$TDLIB_BUILD/web"
	install="$TDLIB_INSTALL/web"
	stamp="$config/.tdlib-build.stamp"
	if [ -f "$config/CMakeCache.txt" ]; then
		rm -rf "$config"
	fi
	mkdir -p "$config" "$install"
	cmake_file_backup="$config/tdlib-CMakeLists.txt.backup"
	cp "$TDLIB_SRC/CMakeLists.txt" "$cmake_file_backup"
	trap 'cp "$cmake_file_backup" "$TDLIB_SRC/CMakeLists.txt"; rm -f "$cmake_file_backup"' EXIT
	sed 's/EXTRA_EXPORTED_RUNTIME_METHODS/EXPORTED_RUNTIME_METHODS/g' "$cmake_file_backup" > "$TDLIB_SRC/CMakeLists.txt"
	host_config="$TDLIB_BUILD/host-generation"
	"$CMAKE" -S "$TDLIB_SRC" -B "$host_config" -G "${CMAKE_GENERATOR:-Unix Makefiles}" \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DTD_ENABLE_JNI=OFF -DTD_ENABLE_DOTNET=OFF -DTD_ENABLE_NATIVE=OFF
	"$CMAKE" --build "$host_config" --target prepare_cross_compiling --parallel "${CMAKE_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

	emcc_version=$(emcc --version | shasum | awk '{print $1}')
	fingerprint=$(printf '%s\n' "$TDLIB_VERSION" web "$emcc_version" | shasum | awk '{print $1}')
	if [ -f "$install/td_wasm.js" ] && [ -f "$install/td_wasm.wasm" ]; then
		echo "TDLib (web) is cached at $install"
		printf '%s\n' "$fingerprint" > "$stamp"
		return
	fi

	emcmake "$CMAKE" -S "$TDLIB_SRC" -B "$config" -G "${CMAKE_GENERATOR:-Unix Makefiles}" \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$install" \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DCMAKE_HAVE_LIBC_PTHREAD=1 \
		$OPENSSL_WEB_ARGS \
		-DTD_ENABLE_JNI=OFF -DTD_ENABLE_DOTNET=OFF -DTD_ENABLE_NATIVE=OFF
	emmake "$CMAKE" --build "$config" --target td_wasm --parallel "${CMAKE_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

	js_file=$(find "$config" -maxdepth 1 -name 'td_wasm.js' -type f -print -quit)
	wasm_file=$(find "$config" -maxdepth 1 -name 'td_wasm.wasm' -type f -print -quit)
	[ -n "$js_file" ] && [ -n "$wasm_file" ] || die "TDLib WebAssembly build completed without td_wasm.js and td_wasm.wasm"
	cp "$js_file" "$install/td_wasm.js"
	cp "$wasm_file" "$install/td_wasm.wasm"
	printf '%s\n' "$fingerprint" > "$stamp"
}

go_env_for_tdlib() {
	platform=$1
	install="$TDLIB_INSTALL/$platform"
	export CGO_ENABLED=1
	export CGO_CFLAGS="-I$install/include ${CGO_CFLAGS:-}"
	if [ "$platform" = macos ]; then
		export CGO_LDFLAGS="-L$install/lib -Wl,-rpath,$install/lib -ltdjson ${CGO_LDFLAGS:-}"
	else
		export CGO_LDFLAGS="-L$install/lib -ltdjson ${CGO_LDFLAGS:-}"
	fi
}

fyne_cmd() {
	if command -v fyne >/dev/null 2>&1; then
		echo fyne
		return
	fi
	if [ -x "$HOME/go/bin/fyne" ]; then
		echo "$HOME/go/bin/fyne"
		return
	fi
	die "Fyne CLI was not found. Install it with: $GO install fyne.io/fyne/v2/cmd/fyne@latest"
}

build_macos() {
	tdlib_build macos
	go_env_for_tdlib macos
	mkdir -p "$BUILD_ROOT" "$DIST_ROOT/macos"
	"$GO" build -tags telety_tdlib -trimpath -o "$BUILD_ROOT/telety-macos" ./cmd
	if fyne=$(fyne_cmd 2>/dev/null); then
		(
			cd "$DIST_ROOT/macos"
			"$fyne" package -os darwin -name "$APP_NAME" -appID "$APP_ID" -icon "$ROOT_DIR/cmd/Icon.png" -sourceDir "$ROOT_DIR/cmd"
		)
	else
		mkdir -p "$DIST_ROOT/macos/$APP_NAME.app/Contents/MacOS"
		cp "$BUILD_ROOT/telety-macos" "$DIST_ROOT/macos/$APP_NAME.app/Contents/MacOS/$APP_NAME"
		echo "Fyne CLI not found; created a runnable .app bundle without generated metadata."
	fi
}

build_android() {
	tdlib_build android
	go_env_for_tdlib android
	android_ndk
	need_cmd java
	fyne=$(fyne_cmd)
	mkdir -p "$DIST_ROOT/android"
	(
		cd "$DIST_ROOT/android"
		ANDROID_NDK="$ANDROID_NDK" "$fyne" package -tags telety_tdlib -os android -appID "$APP_ID" -name "$APP_NAME" -icon "$ROOT_DIR/cmd/Icon.png" -sourceDir "$ROOT_DIR/cmd"
	)
}

build_web() {
	tdlib_build web
	check_common
	fyne=$(fyne_cmd)
	mkdir -p "$DIST_ROOT/web/tdlib"
	cp "$TDLIB_INSTALL/web/td_wasm.js" "$DIST_ROOT/web/tdlib/td_wasm.js"
	cp "$TDLIB_INSTALL/web/td_wasm.wasm" "$DIST_ROOT/web/tdlib/td_wasm.wasm"
	(
		cd "$DIST_ROOT/web"
		"$fyne" package -os web -icon "$ROOT_DIR/cmd/Icon.png" -sourceDir "$ROOT_DIR/cmd"
	)
}

run_macos() {
	tdlib_build macos
	go_env_for_tdlib macos
	exec "$GO" run -tags telety_tdlib ./cmd
}

run_android() {
	build_android
	adb=$(android_adb)
	devices=$($adb devices | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }')
	[ "$devices" -gt 0 ] || die "No Android device or emulator is connected. Start an emulator or connect a device with USB debugging enabled."
	adb_device_args=
	if [ -n "${ANDROID_SERIAL:-}" ]; then
		adb_device_args="-s $ANDROID_SERIAL"
	fi
	$adb $adb_device_args install -r "$DIST_ROOT/android/$APP_NAME.apk"
	$adb $adb_device_args shell monkey -p "$APP_ID" 1 >/dev/null
}

run_web() {
	build_web
	python=$(python_cmd)
	echo "Web application: http://$WEB_HOST:$WEB_PORT/wasm/"
	exec "$python" -m http.server "$WEB_PORT" --bind "$WEB_HOST" --directory "$DIST_ROOT/web"
}

case "${1:-}" in
	setup)
		check_common
		git -C "$ROOT_DIR" submodule update --init -- "$TDLIB_SUBMODULE_PATH"
		"$GO" mod tidy
		if ! command -v fyne >/dev/null 2>&1 && [ ! -x "$HOME/go/bin/fyne" ]; then
			echo "Fyne CLI is not installed. Install it with: $GO install fyne.io/fyne/v2/cmd/fyne@latest"
		fi
		;;
	submodules)
		check_common
		git -C "$ROOT_DIR" submodule update --init -- "$TDLIB_SUBMODULE_PATH"
		;;
	tdlib) tdlib_build "${TDLIB_PLATFORM:-macos}" ;;
	tdlib-macos) tdlib_build macos ;;
	tdlib-android) tdlib_build android ;;
	tdlib-web) tdlib_build web ;;
	build)
		case "${2:-}" in
			macos) build_macos ;;
			android) build_android ;;
			web) build_web ;;
			*) die "Unknown target '${2:-}'. Choose macos, android, or web." ;;
		esac
		;;
	run)
		case "${2:-$(uname -s | tr '[:upper:]' '[:lower:]')}" in
			macos|darwin|pc) run_macos ;;
			android|phone) run_android ;;
			web) run_web ;;
			*) die "Unknown run platform '${2:-}'. Use make run for a PC, phone, or web browser." ;;
		esac
		;;
	*) die "Usage: $0 setup|submodules|tdlib|tdlib-macos|tdlib-android|build <macos|android|web>|run [macos|android]" ;;
esac