#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Exercise the real AppState and beta views with isolated stores, without loading
# speech models or launching an app that would touch the user's notebook.
swift build --package-path MurmurCore --configuration debug
core_bin=$(swift build --package-path MurmurCore --configuration debug --show-bin-path)
mkdir -p .build/beta-checks
swiftc -swift-version 6 -parse-as-library \
  -I "$core_bin/Modules" -module-cache-path "$core_bin/ModuleCache" \
  App/Sources/AppState.swift App/Sources/System/HotkeyMonitor.swift \
  App/Sources/UI/Theme.swift App/Sources/UI/ScratchpadView.swift \
  App/Sources/UI/DictationDetailView.swift App/Sources/UI/Beta/*.swift \
  tools/Tests/BetaStateChecks.swift "$core_bin/MurmurCore.build/"*.swift.o \
  -o .build/beta-checks/check-beta-state
.build/beta-checks/check-beta-state
