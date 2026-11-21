#!/bin/zsh
# Builds Cavok and installs it to /Applications/Cavok.app.
# Usage: ./build.sh            release build, install
#        ./build.sh --debug    debug build, install
#        ./build.sh --open     install, then quit the running copy and open the new one
set -euo pipefail
here=${0:A:h}
name="Cavok"
scratch="$HOME/Library/Developer/$name/build"
config=release
[[ " $* " == *" --debug "* ]] && config=debug

identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"' || true)
fi
[[ -n "$identity" ]] || identity=-

build_log=$(mktemp "${TMPDIR:-/tmp}/cavok-build.XXXXXX")
set +e
swift build -c $config --package-path "$here" --scratch-path "$scratch" >"$build_log" 2>&1
build_status=$?
set -e
grep -E "error|warning|Build complete" "$build_log" | grep -v "^\[" || true
rm -f "$build_log"
if [[ $build_status -ne 0 ]]; then
  echo "build failed"
  exit "$build_status"
fi
bin="$scratch/$config/$name"
filter="$scratch/$config/CavokGuardFilter"
[[ -x "$bin" && -x "$filter" ]] || { echo "build failed"; exit 1; }
stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
if [[ -n "$stale" ]]; then
  echo "build failed: binary is older than $stale"
  swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error" | head -20
  exit 1
fi

stage=$(mktemp -d "${TMPDIR:-/tmp}/cavok-app.XXXXXX")
app="$stage/$name.app"
build_id=$(date +%Y%m%d%H%M)
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__BUILD__/$build_id/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
if [[ -f "$here/Icon/AppIcon.icon/Assets/mark.png" ]]; then
  icns="$here/Resources/AppIcon.icns"
  if [[ ! -f "$icns" || "$here/Icon/AppIcon.icon/Assets/mark.png" -nt "$icns" ]]; then
    "$here/tools/make_icon.sh"
  fi
  cp -X "$icns" "$app/Contents/Resources/"
fi

ext="$app/Contents/Library/SystemExtensions/com.isaaccheung.cavok.guard.systemextension"
mkdir -p "$ext/Contents/MacOS"
cp "$filter" "$ext/Contents/MacOS/CavokGuardFilter"
sed -e "s/__BUILD__/$build_id/" "$here/Info-filter.plist.in" > "$ext/Contents/Info.plist"
xattr -cr "$app"

filter_signed=0
app_profile="${CAVOK_APP_PROFILE:-}"
filter_profile="${CAVOK_FILTER_PROFILE:-}"
if [[ "$identity" != "-" && -f "$app_profile" && -f "$filter_profile" ]]; then
  cp "$filter_profile" "$ext/Contents/embedded.provisionprofile"
  cp "$app_profile" "$app/Contents/embedded.provisionprofile"
  set +e
  codesign --force --sign "$identity" --entitlements "$here/CavokGuardFilter.entitlements" "$ext" >/tmp/cavok-sign-filter.txt 2>&1
  filter_status=$?
  codesign --force --sign "$identity" --entitlements "$here/Cavok.entitlements" "$app" >/tmp/cavok-sign-app.txt 2>&1
  app_status=$?
  set -e
  if [[ $filter_status -eq 0 && $app_status -eq 0 ]]; then
    filter_signed=1
  fi
fi
if [[ $filter_signed -eq 0 ]]; then
  rm -rf "$app/Contents/Library"
  rm -f "$app/Contents/embedded.provisionprofile"
  codesign --force --sign "$identity" "$app" 2>&1 | grep -v "replacing existing signature" || true
  echo "packet drop is not signed. Guard will show that it is not armed."
else
  echo "packet drop signed with $identity"
fi

dest="/Applications/$name.app"
installed=0
if mkdir -p /Applications && rm -rf "$dest" && cp -R "$app" "$dest"; then
  installed=1
else
  quoted_dest=$(printf '%q' "$dest")
  quoted_app=$(printf '%q' "$app")
  set +e
  osascript -e "do shell script \"rm -rf $quoted_dest && cp -R $quoted_app $quoted_dest\" with administrator privileges"
  copy_status=$?
  set -e
  [[ $copy_status -eq 0 ]] && installed=1
fi
rm -rf "$stage"
[[ $installed -eq 1 ]] || { echo "install failed"; exit 1; }
rm -rf "$HOME/Applications/$name.app"
echo "installed $dest (signed: ${identity})"

if [[ " $* " == *" --open "* ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  sleep 0.5
  open "$dest"
fi
