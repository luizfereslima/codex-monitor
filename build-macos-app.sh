#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR="$PROJECT_DIR/CodexPulse.app"
CONTENTS="$APP_DIR/Contents"

mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"
cp "$PROJECT_DIR/CodexPulse.icns" "$CONTENTS/Resources/CodexPulse.icns"
cp "$PROJECT_DIR/usage.py" "$CONTENTS/Resources/usage.py"
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Codex Pulse</string>
  <key>CFBundleDisplayName</key><string>Codex Pulse</string>
  <key>CFBundleIdentifier</key><string>com.criacode.codex-pulse</string>
  <key>CFBundleExecutable</key><string>CodexPulse</string>
  <key>CFBundleIconFile</key><string>CodexPulse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

swiftc -O -framework AppKit "$PROJECT_DIR/CodexPulse.swift" -o "$CONTENTS/MacOS/CodexPulse"

LAUNCHER_DIR="$PROJECT_DIR/Iniciar Codex Pulse.app"
LAUNCHER_CONTENTS="$LAUNCHER_DIR/Contents"
mkdir -p "$LAUNCHER_CONTENTS/MacOS" "$LAUNCHER_CONTENTS/Resources"
cp "$PROJECT_DIR/CodexPulse.icns" "$LAUNCHER_CONTENTS/Resources/CodexPulse.icns"
cat > "$LAUNCHER_CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Iniciar Codex Pulse</string>
  <key>CFBundleDisplayName</key><string>Iniciar Codex Pulse</string>
  <key>CFBundleIdentifier</key><string>com.criacode.codex-pulse.launcher</string>
  <key>CFBundleExecutable</key><string>LaunchCodexPulse</string>
  <key>CFBundleIconFile</key><string>CodexPulse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
cat > "$LAUNCHER_CONTENTS/MacOS/LaunchCodexPulse" <<'SCRIPT'
#!/bin/sh
set -eu
SCRIPT
printf "PROJECT_DIR='%s'\n" "$PROJECT_DIR" >> "$LAUNCHER_CONTENTS/MacOS/LaunchCodexPulse"
cat >> "$LAUNCHER_CONTENTS/MacOS/LaunchCodexPulse" <<'SCRIPT'
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! "$PROJECT_DIR/iniciar-monitor.command" >/tmp/codex-monitor-launch.log 2>&1; then
  /usr/bin/osascript -e 'display alert "Codex Pulse" message "Falha ao iniciar. Consulte /tmp/codex-monitor-launch.log" as critical'
fi
SCRIPT
chmod +x "$LAUNCHER_CONTENTS/MacOS/LaunchCodexPulse"
echo "App pronto: $APP_DIR"
echo "Iniciador pronto: $LAUNCHER_DIR"
