#!/bin/sh
# Builds SessionBar.app with the Command Line Tools (no Xcode) and installs it in ~/Applications.
set -eu
cd "$(dirname "$0")"

mkdir -p build
swiftc -swift-version 5 Sources/Logic.swift Tests/main.swift -o build/tests
./build/tests

APP=build/SessionBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -swift-version 5 -parse-as-library Sources/Logic.swift Sources/App.swift -o "$APP/Contents/MacOS/SessionBar"
codesign --force --sign - "$APP"

mkdir -p "$HOME/Applications"
pkill -x SessionBar || true
rm -rf "$HOME/Applications/SessionBar.app"
cp -R "$APP" "$HOME/Applications/"
echo "Installed $HOME/Applications/SessionBar.app"
