#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
app_dir="$project_dir/Ego Tab Search.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources/bridge" "$app_dir/Contents/Resources/licenses"
iconset="$project_dir/build/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$project_dir/Assets/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$project_dir/Assets/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
swiftc -swift-version 5 -target arm64-apple-macosx13.0 -O -framework AppKit -framework SwiftUI -framework Carbon \
  "$project_dir/Sources/BrowserBridge.swift" "$project_dir/Sources/SearchView.swift" "$project_dir/Sources/App.swift" \
  -o "$app_dir/Contents/MacOS/EgoTabSearch"
cp "$project_dir/bridge/mapping.mjs" "$project_dir/bridge/runtime.mjs" "$app_dir/Contents/Resources/bridge/"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/licenses/beui-MIT.txt" "$project_dir/LICENSE" "$app_dir/Contents/Resources/licenses/"
codesign --force --sign - "$app_dir"
print "Built $app_dir"
