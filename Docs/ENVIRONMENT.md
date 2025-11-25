# Legacy Treasure Chest - Development Environment

**Last Updated:** 2025-01-14  
**Status:** ACTIVE

## Required Development Setup

### macOS
- **Version:** macOS Tahoe 15.2.1 or later
- **Hardware:** Apple Silicon (M1/M2/M3) recommended
- **Disk Space:** 15GB minimum for Xcode + Simulators

### Xcode
- **Version:** 16.1 or later
- **Installation:** Mac App Store or developer.apple.com
- **Command Line Tools:** Installed automatically with Xcode

### Apple Developer Account
- **Requirement:** Paid membership ($99/year)
- **Purpose:** 
  - Sign in with Apple capability
  - Device provisioning
  - TestFlight distribution
- **Sign up:** developer.apple.com

---

## Project Setup (First Time)

### 1. Clone/Create Project
```bash
cd ~/Documents/Legacy_Treasure_Chest
# Project already created in Xcode
```

### 2. Open in Xcode
```bash
open LegacyTreasureChest.xcodeproj
```

### 3. Configure Signing

1. Select **LegacyTreasureChest** project
2. Select **LegacyTreasureChest** target
3. **Signing & Capabilities** tab
4. **Team:** Select your Apple Developer team
5. **Automatically manage signing:** ✅ Enabled

### 4. Verify Capabilities

Ensure these are enabled (should be automatic):
- ✅ Sign in with Apple
- ✅ iCloud (will configure in Phase 1B)

---

## Build Configuration

### Debug (Development)
```
Configuration: Debug
Optimization: None (-Onone)
Swift Compiler: Strict Concurrency Checking
Minimum Deployment: iOS 18.0
```

### Release (Production)
```
Configuration: Release
Optimization: Optimize for Speed (-O)
Swift Compiler: Strict Concurrency Checking
Minimum Deployment: iOS 18.0
Code Signing: Automatic
```

---

## iOS Simulator Setup

### Recommended Simulators

Install these via Xcode → Settings → Platforms:

**Primary Testing:**
- iPhone 15 Pro (iOS 18.2) - Apple Intelligence capable
- iPhone 15 (iOS 18.2) - Fallback testing

**Secondary Testing:**
- iPhone 14 Pro (iOS 18.2) - Older hardware
- iPad Pro 13" (iOS 18.2) - Future iPad support

### Simulator Limitations

**What works:**
- ✅ SwiftUI previews
- ✅ Sign in with Apple (test mode)
- ✅ SwiftData persistence
- ✅ File system access
- ✅ Most Apple Intelligence features

**What doesn't work:**
- ❌ Real Sign in with Apple credentials
- ❌ Some Apple Intelligence features (device-specific)
- ❌ Camera (uses sample images)
- ❌ Microphone (uses sample audio)
- ❌ Actual CloudKit sync

**Solution:** Test on physical iPhone 15 Pro for full functionality

---

## Physical Device Setup (Part 3)

**Will cover in Response 3:**
- Connect iPhone 15 to Mac
- Enable Developer Mode
- Install app on device
- Test Apple Intelligence features
- Configure iCloud sync

---

## API Keys & Secrets

### Gemini API Key

**Setup (Part 3):**
1. Obtain key from ai.google.dev
2. Store in Xcode configuration
3. Never commit to git

**Current Status:** Will configure in Part 3

### Sign in with Apple

**Configuration:**
- Automatic via Xcode capabilities
- No API key required
- Uses team's App ID

---

## Project Structure
```
~/Documents/Legacy_Treasure_Chest/
├── LegacyTreasureChest/           # Xcode project
│   ├── App/
│   ├── Core/
│   ├── Data/
│   ├── Features/
│   └── UI/
├── LegacyTreasureChest.xcodeproj  # Xcode project file
├── docs/                           # Documentation
│   ├── ARCHITECTURE.md
│   ├── DATA-MODEL.md
│   ├── ENVIRONMENT.md             # This file
│   └── [more docs in Part 2]
└── archive/                        # Old iterations
    └── 2024-iteration/
```

---

## Common Build Issues

### Issue: "No such module 'SwiftData'"

**Solution:**
- Ensure deployment target is iOS 18.0+
- Clean build folder: Product → Clean Build Folder
- Restart Xcode

### Issue: "Cannot find type 'LTCUser' in scope"

**Solution:**
- Ensure all files added to target
- Check file membership in File Inspector
- Rebuild project

### Issue: "Signing certificate expired"

**Solution:**
- Xcode → Settings → Accounts
- Select Apple ID → Manage Certificates
- Click "+" → iOS Development
- Restart Xcode

---

## Testing Environment

### Unit Tests (Phase 1B)
```
Location: LegacyTreasureChestTests/
Target: LegacyTreasureChestTests
Framework: XCTest
Run: Product → Test (⌘U)
```

### UI Tests (Phase 2)
```
Location: LegacyTreasureChestUITests/
Target: LegacyTreasureChestUITests
Framework: XCTest
Run: Product → Test (⌘U)
```

---

## Performance Profiling

### Instruments

**Memory Leaks:**
```bash
Product → Profile → Leaks
```

**Time Profiler:**
```bash
Product → Profile → Time Profiler
```

**File Activity:**
```bash
Product → Profile → File Activity
```

---

## Version Control (To Be Set Up)

### Git Repository

**Initialize:**
```bash
cd ~/Documents/Legacy_Treasure_Chest/LegacyTreasureChest
git init
git add .
git commit -m "Initial commit - Phase 1A foundation"
```

### .gitignore

Create `.gitignore`:
```
# Xcode
build/
*.xcuserstate
*.xcworkspace
xcuserdata/

# Swift
*.swiftmodule

# API Keys
Config.xcconfig

# macOS
.DS_Store

# Documentation build artifacts
docs/build/
```

---

## Continuous Integration (Future)

**Planned for Phase 2:**
- Xcode Cloud or GitHub Actions
- Automated testing on commit
- TestFlight deployment

---

## Troubleshooting

### Reset Simulator

If Simulator behaves oddly:
```
Device → Erase All Content and Settings
```

### Reset SwiftData

Delete app from Simulator:
- Long press app icon → Delete App
- Reinstall via Xcode

### Clean Build

When things break mysteriously:
1. Product → Clean Build Folder (⇧⌘K)
2. Quit Xcode
3. Delete DerivedData:
```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
```
4. Reopen Xcode

---

## Support Resources

### Documentation
- [Swift.org](https://swift.org/documentation/)
- [Apple Developer](https://developer.apple.com/documentation/)
- [SwiftData Guide](https://developer.apple.com/xcode/swiftdata/)

### Community
- [Swift Forums](https://forums.swift.org)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/swiftui)
- [Apple Developer Forums](https://developer.apple.com/forums/)

---

## Next Steps

**Current Status:** Phase 1A Complete ✅
- Foundation code implemented
- Documentation created
- Project builds successfully

**Next:** Part 2 - Feature Implementation
- Authentication module
- Audio recording module
- Run on Simulator

**Then:** Part 3 - Device Setup
- Connect iPhone
- Configure Gemini API
- Test on device
- Enable CloudKit

---

## Change Log

- **2025-01-14:** Initial environment documentation
  - Development setup documented
  - Build configuration specified
  - Simulator setup outlined
  - Physical device setup deferred to Part 3