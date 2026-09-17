#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --package-path MurmurCore --configuration debug
core_bin=$(swift build --package-path MurmurCore --configuration debug --show-bin-path)
mkdir -p .build/preview
swiftc -swift-version 6 -parse-as-library \
  -I "$core_bin/Modules" -module-cache-path "$core_bin/ModuleCache" \
  App/Sources/AppState.swift App/Sources/System/HotkeyMonitor.swift \
  App/Sources/UI/Theme.swift App/Sources/UI/ScratchpadView.swift \
  App/Sources/UI/DictationDetailView.swift App/Sources/UI/Beta/*.swift \
  App/Sources/UI/FeedView.swift App/Sources/UI/MainWindowView.swift \
  App/Sources/UI/StatusDot.swift App/Sources/UI/OverlayView.swift \
  tools/Preview/NightSkyPreview.swift "$core_bin/MurmurCore.build/"*.swift.o \
  -o .build/preview/night-sky-preview
.build/preview/night-sky-preview
