#!/usr/bin/env swift

import Foundation

// MARK: - Configuration

struct Config {
    static let deviceName = ProcessInfo.processInfo.environment["DEVICE_NAME"] ?? "iPhone 15 Pro Max"
    static let outputDir = ProcessInfo.processInfo.environment["OUTPUT_DIR"] ?? "screenshots"
    static let bundleId = ProcessInfo.processInfo.environment["BUNDLE_ID"] ?? ""
    static let appPath = ProcessInfo.processInfo.environment["APP_PATH"] // Path to extracted .app
    static let credentialsJson = ProcessInfo.processInfo.environment["CREDENTIALS"]
    
    static var credentials: Credentials? {
        guard let json = credentialsJson, !json.isEmpty else { return nil }
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }
}

struct Credentials: Codable {
    let email: String?
    let password: String?
    let skipButtonText: String?
    let deepLink: String?
}

struct NavigationInfo {
    var urlSchemes: [String] = []
    var deepLinkPaths: [String] = []
    var commonScreens: [String] = []
}

struct AppAnalysis {
    let bundleId: String
    let appPath: String?
    var navigationInfo: NavigationInfo = NavigationInfo()
}

// MARK: - Simulator Controller

class SimulatorController {
    let deviceName: String
    let bundleId: String
    let outputDir: String
    var screenshotCount = 0
    var capturedScreenHashes: Set<String> = []
    
    init(deviceName: String, bundleId: String, outputDir: String) {
        self.deviceName = deviceName
        self.bundleId = bundleId
        self.outputDir = outputDir
        
        // Create output directory
        try? FileManager.default.createDirectory(
            atPath: outputDir,
            withIntermediateDirectories: true
        )
    }
    
    // MARK: - Shell Commands
    
    @discardableResult
    func shell(_ command: String) -> (output: String, exitCode: Int32) {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/bash"
        task.standardInput = nil
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ("Error: \(error)", 1)
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return (output.trimmingCharacters(in: .whitespacesAndNewlines), task.terminationStatus)
    }
    
    // MARK: - App Control
    
    func injectUserDefaults(_ defaults: [(key: String, value: String, type: String)]) {
        // Inject UserDefaults before launching app
        // This can skip onboarding for many apps
        for (key, value, type) in defaults {
            let command: String
            switch type {
            case "bool":
                command = "xcrun simctl spawn '\(deviceName)' defaults write '\(bundleId)' '\(key)' -bool \(value)"
            case "string":
                command = "xcrun simctl spawn '\(deviceName)' defaults write '\(bundleId)' '\(key)' '\(value)'"
            case "int":
                command = "xcrun simctl spawn '\(deviceName)' defaults write '\(bundleId)' '\(key)' -int \(value)"
            default:
                command = "xcrun simctl spawn '\(deviceName)' defaults write '\(bundleId)' '\(key)' '\(value)'"
            }
            shell(command)
        }
    }
    
    func launchApp(withArguments args: [String] = []) {
        print("Launching app: \(bundleId)")
        
        if args.isEmpty {
            shell("xcrun simctl launch '\(deviceName)' '\(bundleId)'")
        } else {
            // Launch with arguments
            let argsString = args.map { "'\($0)'" }.joined(separator: " ")
            shell("xcrun simctl launch '\(deviceName)' '\(bundleId)' \(argsString)")
        }
        sleep(3) // Wait for app to launch
    }
    
    func terminateApp() {
        shell("xcrun simctl terminate '\(deviceName)' '\(bundleId)'")
    }
    
    func openDeepLink(_ url: String) {
        print("Opening deep link: \(url)")
        shell("xcrun simctl openurl '\(deviceName)' '\(url)'")
        sleep(2)
    }
    
    // MARK: - Screenshot Capture
    
    func captureScreenshot(_ name: String) {
        screenshotCount += 1
        let filename = String(format: "%02d_%@.png", screenshotCount, name)
        let path = "\(outputDir)/\(filename)"
        
        let result = shell("xcrun simctl io '\(deviceName)' screenshot '\(path)'")
        if result.exitCode == 0 {
            print("📸 Captured: \(filename)")
        } else {
            print("❌ Failed to capture: \(filename)")
        }
    }
    
    func captureUniqueScreenshot(_ name: String) {
        // Capture to temp file first
        let tempPath = "\(outputDir)/temp_screenshot.png"
        shell("xcrun simctl io '\(deviceName)' screenshot '\(tempPath)'")
        
        // Get file hash to detect duplicates
        let hashResult = shell("md5 -q '\(tempPath)'")
        let hash = hashResult.output
        
        if capturedScreenHashes.contains(hash) {
            print("⏭️ Skipping duplicate screen")
            try? FileManager.default.removeItem(atPath: tempPath)
            return
        }
        
        capturedScreenHashes.insert(hash)
        
        // Move to final location
        screenshotCount += 1
        let filename = String(format: "%02d_%@.png", screenshotCount, name)
        let finalPath = "\(outputDir)/\(filename)"
        try? FileManager.default.moveItem(atPath: tempPath, toPath: finalPath)
        print("📸 Captured: \(filename)")
    }
    
    // MARK: - UI Interaction
    
    func tap(x: Int, y: Int) {
        shell("xcrun simctl io '\(deviceName)' tap \(x) \(y)")
        usleep(500000) // 0.5 second
    }
    
    func typeText(_ text: String) {
        // Escape special characters
        let escaped = text.replacingOccurrences(of: "'", with: "'\\''")
        shell("xcrun simctl io '\(deviceName)' pbcopy '\(escaped)'")
        shell("xcrun simctl io '\(deviceName)' keyboard paste")
    }
    
    func swipeLeft() {
        // Swipe from right to left (for onboarding screens)
        let deviceWidth = deviceName.contains("iPad") ? 1024 : 393
        let deviceHeight = deviceName.contains("iPad") ? 1366 : 852
        let centerY = deviceHeight / 2
        
        shell("xcrun simctl io '\(deviceName)' swipe \(deviceWidth - 50) \(centerY) 50 \(centerY)")
        usleep(800000)
    }
    
    func swipeDown() {
        let deviceWidth = deviceName.contains("iPad") ? 1024 : 393
        let deviceHeight = deviceName.contains("iPad") ? 1366 : 852
        let centerX = deviceWidth / 2
        
        shell("xcrun simctl io '\(deviceName)' swipe \(centerX) \(deviceHeight - 100) \(centerX) 100")
        usleep(500000)
    }
    
    func swipeUp() {
        let deviceWidth = deviceName.contains("iPad") ? 1024 : 393
        let deviceHeight = deviceName.contains("iPad") ? 1366 : 852
        let centerX = deviceWidth / 2
        
        shell("xcrun simctl io '\(deviceName)' swipe \(centerX) 100 \(centerX) \(deviceHeight - 100)")
        usleep(500000)
    }
    
    func pressHome() {
        shell("xcrun simctl io '\(deviceName)' keycode home")
        usleep(500000)
    }
    
    // MARK: - UI Element Detection (using accessibility)
    
    func getAccessibilityTree() -> String {
        // Use lldb or accessibility inspector to get UI hierarchy
        // For now, we'll use a simpler approach based on screen capture and OCR
        // This is a placeholder - in production, use XCTest framework
        return shell("xcrun simctl spawn '\(deviceName)' accessibility_inspector 2>/dev/null || echo ''").output
    }
}

// MARK: - IPA Analysis

class IPAAnalyzer {
    static func extractURLSchemes(from appPath: String) -> [String] {
        var schemes: [String] = []
        let infoPlistPath = "\(appPath)/Info.plist"
        
        // Use plutil to extract CFBundleURLTypes
        let result = shell("plutil -extract CFBundleURLTypes json '\(infoPlistPath)' 2>/dev/null || echo '[]'")
        
        if let data = result.output.data(using: .utf8),
           let urlTypes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for urlType in urlTypes {
                if let urlSchemes = urlType["CFBundleURLSchemes"] as? [String] {
                    schemes.append(contentsOf: urlSchemes)
                }
            }
        }
        
        return schemes
    }
    
    static func extractCommonScreens() -> [String] {
        // Common screen names/identifiers
        return [
            "home", "main", "dashboard", "feed", "timeline",
            "profile", "settings", "account", "user",
            "discover", "explore", "search", "browse",
            "messages", "chat", "inbox",
            "notifications", "alerts",
            "library", "saved", "favorites",
            "create", "new", "add",
            "menu", "more", "options"
        ]
    }
    
    static func generateDeepLinks(schemes: [String], screens: [String]) -> [String] {
        var deepLinks: [String] = []
        
        for scheme in schemes {
            // Try scheme://screen format
            for screen in screens {
                deepLinks.append("\(scheme)://\(screen)")
            }
            
            // Try common patterns
            deepLinks.append("\(scheme)://")
            deepLinks.append("\(scheme)://main")
            deepLinks.append("\(scheme)://home")
            deepLinks.append("\(scheme)://dashboard")
        }
        
        return deepLinks
    }
    
    static func analyzeApp(appPath: String?, bundleId: String) -> AppAnalysis {
        var analysis = AppAnalysis(bundleId: bundleId, appPath: appPath)
        
        if let appPath = appPath, FileManager.default.fileExists(atPath: appPath) {
            // Extract URL schemes
            let schemes = extractURLSchemes(from: appPath)
            analysis.navigationInfo.urlSchemes = schemes
            
            // Generate deep links
            let commonScreens = extractCommonScreens()
            analysis.navigationInfo.commonScreens = commonScreens
            analysis.navigationInfo.deepLinkPaths = generateDeepLinks(schemes: schemes, screens: commonScreens)
            
            print("📱 Extracted \(schemes.count) URL schemes: \(schemes.joined(separator: ", "))")
            print("🔗 Generated \(analysis.navigationInfo.deepLinkPaths.count) potential deep links")
        }
        
        return analysis
    }
    
    static func shell(_ command: String) -> (output: String, exitCode: Int32) {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/bash"
        task.standardInput = nil
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ("Error: \(error)", 1)
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return (output.trimmingCharacters(in: .whitespacesAndNewlines), task.terminationStatus)
    }
}

// MARK: - App Explorer

class AppExplorer {
    let controller: SimulatorController
    let credentials: Credentials?
    let appAnalysis: AppAnalysis
    
    // Common button labels to look for
    let skipButtons = [
        "Skip", "Skip for now", "Not now", "Maybe later",
        "Continue as guest", "Guest", "Demo", "Demo mode",
        "Get Started", "Let's go", "Done", "Dismiss", "Close"
    ]
    
    let loginIndicators = [
        "Log in", "Login", "Sign in", "Sign In",
        "Email", "Password", "Username"
    ]
    
    let onboardingIndicators = [
        "Next", "Continue", "Get Started", "Welcome",
        "Swipe", "Tutorial"
    ]
    
    // Common UserDefaults keys that apps use to track onboarding
    let onboardingUserDefaults = [
        ("hasSeenOnboarding", "true", "bool"),
        ("onboardingComplete", "true", "bool"),
        ("hasCompletedOnboarding", "true", "bool"),
        ("isOnboardingComplete", "true", "bool"),
        ("onboardingShown", "true", "bool"),
        ("firstLaunch", "false", "bool"),
        ("hasLaunchedBefore", "true", "bool"),
        ("skipOnboarding", "true", "bool"),
        ("tutorialCompleted", "true", "bool"),
        ("welcomeShown", "true", "bool")
    ]
    
    // Common launch arguments to skip onboarding
    let skipOnboardingArgs = [
        "-skipOnboarding",
        "-UITests",
        "-disableOnboarding",
        "-skipTutorial",
        "-testMode",
        "-automation"
    ]
    
    // Tab bar positions (approximate for common layouts)
    let tabPositions = [
        (x: 60, label: "Tab 1"),
        (x: 160, label: "Tab 2"),
        (x: 260, label: "Tab 3"),
        (x: 360, label: "Tab 4"),
        (x: 460, label: "Tab 5")
    ]
    
    init(controller: SimulatorController, credentials: Credentials?) {
        self.controller = controller
        self.credentials = credentials
        
        // Analyze app for navigation info
        self.appAnalysis = IPAAnalyzer.analyzeApp(
            appPath: Config.appPath,
            bundleId: controller.bundleId
        )
    }
    
    // MARK: - Main Exploration Flow
    
    func explore() {
        let startTime = Date()
        print("\n🚀 Starting app exploration...")
        print("Device: \(controller.deviceName)")
        print("Bundle ID: \(controller.bundleId)")
        print("Start time: \(startTime)")
        
        // Try to skip onboarding BEFORE launching
        print("\n[Step 1/7] Pre-launch onboarding skip...")
        attemptSkipOnboardingPreLaunch()
        
        // Launch the app (with skip arguments if needed)
        print("\n[Step 2/7] Launching app...")
        attemptLaunchWithSkipArgs()
        
        // Capture launch screen
        print("\n[Step 3/7] Capturing launch screen...")
        controller.captureUniqueScreenshot("launch")
        sleep(1)
        
        // Quick check if we're past onboarding
        print("\n[Step 4/7] Handling onboarding...")
        if !attemptSkipOnboardingPostLaunch() {
            // If skip failed, try to navigate through onboarding
            handleOnboarding()
        }
        
        // Handle login if needed
        print("\n[Step 5/7] Handling login...")
        handleLogin()
        
        // Use deep links to navigate directly to screens
        print("\n[Step 5.5/7] Trying deep link navigation...")
        tryDeepLinkNavigation()
        
        // Use provided deep link if available
        if let deepLink = credentials?.deepLink {
            print("  → Trying provided deep link: \(deepLink)")
            controller.openDeepLink(deepLink)
            controller.captureUniqueScreenshot("deep_link_provided")
            sleep(2)
        }
        
        // Explore main app systematically
        print("\n[Step 6/7] Exploring app content...")
        exploreTabs()
        exploreMainContent()
        exploreNavigationStack()
        
        // Generate URL list file
        print("\n[Step 7/7] Generating URL list...")
        generateUrlList()
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("\n✅ Exploration complete!")
        print("Total unique screenshots: \(controller.screenshotCount)")
        print("Total time: \(String(format: "%.1f", elapsed)) seconds")
    }
    
    // MARK: - Onboarding Skip Methods
    
    func attemptSkipOnboardingPreLaunch() {
        print("\n🔧 Attempting to skip onboarding (pre-launch)...")
        
        // Method 1: Inject UserDefaults
        print("  → Injecting common UserDefaults keys...")
        controller.injectUserDefaults(onboardingUserDefaults)
        sleep(1)
        
        // Method 2: Inject Keychain items (if app checks keychain for auth)
        injectKeychainAuth()
    }
    
    func injectKeychainAuth() {
        print("  → Injecting keychain authentication...")
        // Some apps check keychain for auth tokens
        let bundleId = controller.bundleId
        let commands = [
            "security add-generic-password -a '\(bundleId)' -s 'auth_token' -w 'test_token' -U 2>/dev/null || true",
            "security add-generic-password -a '\(bundleId)' -s 'user_id' -w 'test_user' -U 2>/dev/null || true",
            "security add-generic-password -a '\(bundleId)' -s 'isAuthenticated' -w 'true' -U 2>/dev/null || true"
        ]
        
        for cmd in commands {
            controller.shell(cmd)
        }
    }
    
    func injectEnvironmentVariables() {
        print("  → Setting environment variables...")
        // Some apps check environment variables for test mode
        let envVars = [
            "SKIP_ONBOARDING=true",
            "UITESTS_MODE=true",
            "TEST_MODE=true",
            "AUTOMATION=true"
        ]
        
        // Note: simctl doesn't directly support env vars, but we can try via launch arguments
        // This is more of a placeholder for future enhancement
    }
    
    func attemptLaunchWithSkipArgs() {
        // Try launching with skip arguments (limit to first 3 to save time)
        print("  → Launching with skip arguments...")
        let argsToTry = Array(skipOnboardingArgs.prefix(3))
        for arg in argsToTry {
            print("    Trying: \(arg)")
            controller.launchApp(withArguments: [arg])
            sleep(2)
            
            // Check if app launched successfully
            let hash = captureCurrentScreenHash()
            if !hash.isEmpty {
                print("  ✓ Launched with argument: \(arg)")
                return
            }
        }
        
        // Fallback to normal launch
        print("  → Using normal launch")
        controller.launchApp()
    }
    
    func attemptSkipOnboardingPostLaunch() -> Bool {
        print("\n🔍 Checking if onboarding is present...")
        
        // Capture current screen
        controller.captureUniqueScreenshot("check_onboarding")
        
        // Method 1: Try deep links to skip onboarding (NEW!)
        if !appAnalysis.navigationInfo.deepLinkPaths.isEmpty {
            print("  → Trying deep links to bypass onboarding...")
            let priorityLinks = appAnalysis.navigationInfo.deepLinkPaths.filter { link in
                link.contains("://home") || link.contains("://main") || link.contains("://dashboard")
            }
            
            for link in priorityLinks.prefix(3) {
                let beforeHash = captureCurrentScreenHash()
                controller.openDeepLink(link)
                sleep(2)
                
                let afterHash = captureCurrentScreenHash()
                if afterHash != beforeHash && !afterHash.isEmpty {
                    print("  ✓ Deep link bypassed onboarding: \(link)")
                    controller.captureUniqueScreenshot("deeplink_skip")
                    return true
                }
            }
        }
        
        // Method 2: Try skip button positions
        print("  → Trying skip button positions...")
        let skipPositions = [
            (x: 350, y: 50),   // Top right
            (x: 350, y: 100),  // Below status bar
            (x: 200, y: 800),  // Bottom center
            (x: 200, y: 750),  // Above bottom
            (x: 300, y: 50),   // Top right alternative
            (x: 50, y: 50),    // Top left (sometimes skip is here)
        ]
        
        let beforeHash = captureCurrentScreenHash()
        
        for pos in skipPositions {
            controller.tap(x: pos.x, y: pos.y)
            usleep(800000)
            
            let afterHash = captureCurrentScreenHash()
            if afterHash != beforeHash && !afterHash.isEmpty {
                print("  ✓ Screen changed after tap at (\(pos.x), \(pos.y))")
                controller.captureUniqueScreenshot("after_skip")
                return true
            }
        }
        
        // Method 3: Try swiping through quickly (reduced from 5 to 3)
        print("  → Trying quick swipe through...")
        let swipeBeforeHash = captureCurrentScreenHash()
        for i in 0..<3 {
            controller.swipeLeft()
            usleep(500000)
            let swipeAfterHash = captureCurrentScreenHash()
            if swipeAfterHash != swipeBeforeHash && !swipeAfterHash.isEmpty {
                print("  ✓ Screen changed after swipe")
                controller.captureUniqueScreenshot("swipe_skip")
                return true
            }
        }
        
        // Method 4: Try custom skip button text if provided
        if let customSkip = credentials?.skipButtonText {
            print("  → Looking for custom skip: \(customSkip)")
            // Would need OCR/accessibility API here
        }
        
        print("  ⚠️ Could not skip onboarding automatically")
        return false
    }
    
    func captureCurrentScreenHash() -> String {
        let tempPath = "\(controller.outputDir)/temp_hash_check.png"
        controller.shell("xcrun simctl io '\(controller.deviceName)' screenshot '\(tempPath)'")
        let hashResult = controller.shell("md5 -q '\(tempPath)'")
        try? FileManager.default.removeItem(atPath: tempPath)
        return hashResult.output
    }
    
    // MARK: - Onboarding Handler
    
    func handleOnboarding() {
        print("\n📱 Handling onboarding flow...")
        
        var onboardingScreens = 0
        let maxOnboardingScreens = 5 // Reduced from 8
        var lastHash = ""
        var stuckCount = 0
        let maxStuckCount = 2 // Exit if stuck on same screen twice
        
        while onboardingScreens < maxOnboardingScreens {
            print("  → Onboarding screen \(onboardingScreens + 1)/\(maxOnboardingScreens)")
            
            // Capture current screen
            let currentHash = captureCurrentScreenHash()
            if !currentHash.isEmpty {
                controller.captureUniqueScreenshot("onboarding_\(onboardingScreens)")
            }
            
            // Check if we're stuck on the same screen
            if currentHash == lastHash && !currentHash.isEmpty {
                stuckCount += 1
                print("  ⚠️ Same screen detected (stuck count: \(stuckCount))")
                if stuckCount >= maxStuckCount {
                    print("  ⚠️ Stuck on same screen, trying to skip...")
                    trySkipButtons()
                    sleep(2)
                    // Check if we moved past onboarding
                    let newHash = captureCurrentScreenHash()
                    if newHash != currentHash {
                        print("  ✓ Successfully skipped onboarding")
                        break
                    } else {
                        print("  ⚠️ Still stuck, forcing exit from onboarding")
                        break
                    }
                }
            } else {
                stuckCount = 0
            }
            lastHash = currentHash
            
            // Try to advance onboarding
            let nextButtonPositions = [
                (x: 200, y: 750),  // Bottom center iPhone
                (x: 350, y: 800),  // Bottom right iPhone
                (x: 512, y: 1200), // Bottom center iPad
            ]
            
            var advanced = false
            for pos in nextButtonPositions {
                controller.tap(x: pos.x, y: pos.y)
                sleep(1)
                
                // Actually check if screen changed
                let newHash = captureCurrentScreenHash()
                if newHash != currentHash && !newHash.isEmpty {
                    advanced = true
                    print("  ✓ Screen advanced after tap")
                    break
                }
            }
            
            if !advanced {
                // Try swiping left
                print("  → Trying swipe...")
                controller.swipeLeft()
                sleep(1)
                
                // Check if swipe worked
                let newHash = captureCurrentScreenHash()
                if newHash != currentHash && !newHash.isEmpty {
                    advanced = true
                    print("  ✓ Screen advanced after swipe")
                }
            }
            
            onboardingScreens += 1
            
            // Small delay between screens
            usleep(500000)
        }
        
        // Final attempt to skip onboarding
        print("  → Final skip attempt...")
        trySkipButtons()
        sleep(2)
    }
    
    func trySkipButtons() {
        // Try common skip button positions
        let skipPositions = [
            (x: 350, y: 50),   // Top right
            (x: 350, y: 100),  // Below status bar
            (x: 200, y: 800),  // Bottom center
            (x: 200, y: 750),  // Above bottom
        ]
        
        let beforeHash = captureCurrentScreenHash()
        
        for (index, pos) in skipPositions.enumerated() {
            print("    Trying skip position \(index + 1)/\(skipPositions.count) at (\(pos.x), \(pos.y))")
            controller.tap(x: pos.x, y: pos.y)
            usleep(800000)
            
            // Check if screen changed
            let afterHash = captureCurrentScreenHash()
            if afterHash != beforeHash && !afterHash.isEmpty {
                print("    ✓ Screen changed after skip tap")
                return
            }
        }
        
        print("    ⚠️ No skip button found")
    }
    
    // MARK: - Login Handler
    
    func handleLogin() {
        print("\n🔐 Checking for login screen...")
        
        // Capture login screen if present
        controller.captureUniqueScreenshot("login")
        
        guard let creds = credentials else {
            print("No credentials provided, trying to bypass...")
            trySkipButtons()
            return
        }
        
        // Try to fill login form
        if let email = creds.email, let password = creds.password {
            print("Attempting login with provided credentials...")
            
            // Tap email field (common positions)
            controller.tap(x: 200, y: 300)
            sleep(1)
            controller.typeText(email)
            
            // Tap password field
            controller.tap(x: 200, y: 400)
            sleep(1)
            controller.typeText(password)
            
            // Tap login button
            controller.tap(x: 200, y: 500)
            sleep(3)
        }
        
        // Check for custom skip button
        if let customSkip = creds.skipButtonText {
            print("Looking for custom skip button: \(customSkip)")
            // Would use accessibility/OCR to find and tap
        }
        
        // Use deep link if provided (already handled in main explore flow)
    }
    
    // MARK: - Deep Link Navigation
    
    func tryDeepLinkNavigation() {
        let deepLinks = appAnalysis.navigationInfo.deepLinkPaths
        
        if deepLinks.isEmpty {
            print("  ⚠️ No deep links extracted from app")
            return
        }
        
        print("  → Trying \(deepLinks.count) extracted deep links...")
        
        // Try top priority deep links first (home, main, dashboard)
        let priorityLinks = deepLinks.filter { link in
            link.contains("://home") || 
            link.contains("://main") || 
            link.contains("://dashboard") ||
            link.contains("://")
        }
        
        // Try priority links first
        for (index, link) in priorityLinks.prefix(5).enumerated() {
            print("    Trying deep link \(index + 1)/\(min(5, priorityLinks.count)): \(link)")
            let beforeHash = captureCurrentScreenHash()
            
            controller.openDeepLink(link)
            sleep(2)
            
            let afterHash = captureCurrentScreenHash()
            if afterHash != beforeHash && !afterHash.isEmpty {
                print("    ✓ Deep link worked: \(link)")
                controller.captureUniqueScreenshot("deeplink_\(index + 1)")
                
                // If this deep link worked, try navigating to other screens
                navigateToScreensViaDeepLinks()
                return
            }
        }
        
        print("  ⚠️ No working deep links found")
    }
    
    func navigateToScreensViaDeepLinks() {
        print("  → Navigating to specific screens via deep links...")
        
        // Get unique screens to try (excluding already tried ones)
        let screensToTry = [
            "profile", "settings", "search", "discover",
            "messages", "notifications", "library", "create"
        ]
        
        let schemes = appAnalysis.navigationInfo.urlSchemes
        if schemes.isEmpty {
            return
        }
        
        let primaryScheme = schemes[0]
        
        for (index, screen) in screensToTry.prefix(6).enumerated() {
            let deepLink = "\(primaryScheme)://\(screen)"
            print("    Trying screen: \(screen)")
            
            let beforeHash = captureCurrentScreenHash()
            controller.openDeepLink(deepLink)
            sleep(2)
            
            let afterHash = captureCurrentScreenHash()
            if afterHash != beforeHash && !afterHash.isEmpty {
                print("    ✓ Navigated to \(screen)")
                controller.captureUniqueScreenshot("screen_\(screen)")
            }
        }
    }
    
    // MARK: - Tab Exploration
    
    func exploreTabs() {
        print("\n📑 Exploring tabs...")
        
        // Get device-specific tab bar Y position
        let tabBarY = controller.deviceName.contains("iPad") ? 1330 : 820
        
        // Try different numbers of tabs (most apps have 3-5)
        let deviceWidth = controller.deviceName.contains("iPad") ? 1024 : 393
        
        // Try 4 tabs first (most common), then 3 and 5 if needed
        let tabCounts = [4, 3, 5]
        var foundTabs = false
        
        for tabCount in tabCounts {
            let tabSpacing = deviceWidth / tabCount
            var uniqueScreens = 0
            
            print("Trying \(tabCount) tabs...")
            
            for i in 0..<tabCount {
                let tabX = tabSpacing / 2 + (i * tabSpacing)
                
                print("  → Tapping tab \(i + 1) of \(tabCount) at position (\(tabX), \(tabBarY))")
                let beforeHash = captureCurrentScreenHash()
                controller.tap(x: tabX, y: tabBarY)
                sleep(1)
                
                let afterHash = captureCurrentScreenHash()
                if afterHash != beforeHash && !afterHash.isEmpty {
                    uniqueScreens += 1
                    controller.captureUniqueScreenshot("tab_\(i + 1)")
                    
                    // Only explore content for first 2 tabs to save time
                    if i < 2 {
                        exploreContentInCurrentView()
                    }
                }
            }
            
            // If we found unique screens, assume this is the correct tab count
            if uniqueScreens > 0 {
                print("  ✓ Found \(uniqueScreens) unique tab screens with \(tabCount) tabs")
                foundTabs = true
                break
            }
        }
        
        if !foundTabs {
            print("  ⚠️ No tabs found, continuing with main content exploration")
        }
    }
    
    // MARK: - Main Content Exploration
    
    func exploreMainContent() {
        print("\n🔍 Exploring main content...")
        
        // Grid-based exploration - tap on a grid of positions
        let deviceWidth = controller.deviceName.contains("iPad") ? 1024 : 393
        let deviceHeight = controller.deviceName.contains("iPad") ? 1366 : 852
        
        // Create a smaller 2x3 grid to reduce exploration time
        let gridCols = 2
        let gridRows = 3
        let colSpacing = deviceWidth / (gridCols + 1)
        let rowSpacing = (deviceHeight - 200) / (gridRows + 1) // Leave space for tab bar
        
        var exploredScreens = 0
        let maxExploredScreens = 5 // Limit to prevent infinite loops
        
        for row in 0..<gridRows {
            for col in 0..<gridCols {
                if exploredScreens >= maxExploredScreens {
                    print("  ⚠️ Reached max exploration limit, stopping")
                    break
                }
                
                let x = colSpacing * (col + 1)
                let y = 100 + (rowSpacing * (row + 1))
                
                print("  → Exploring grid position (\(col + 1), \(row + 1))")
                let beforeHash = captureCurrentScreenHash()
                
                controller.tap(x: x, y: y)
                sleep(1)
                
                let afterHash = captureCurrentScreenHash()
                if afterHash != beforeHash && !afterHash.isEmpty {
                    exploredScreens += 1
                    controller.captureUniqueScreenshot("grid_\(col + 1)_\(row + 1)")
                    
                    // Navigate back (don't explore content to save time)
                    navigateBack()
                    sleep(1)
                }
            }
            if exploredScreens >= maxExploredScreens {
                break
            }
        }
        
        // Scroll down and capture more content (reduced from 5 to 3)
        print("Scrolling to find more content...")
        for i in 0..<3 {
            print("  → Scroll \(i + 1)/3")
            controller.swipeDown()
            sleep(1)
            controller.captureUniqueScreenshot("scroll_\(i + 1)")
        }
    }
    
    func exploreContentInCurrentView() {
        // Quick exploration of current view - only try first 2 taps to save time
        let quickTaps = [
            (x: 200, y: 300),
            (x: 200, y: 500)
        ]
        
        for tap in quickTaps {
            let beforeHash = captureCurrentScreenHash()
            controller.tap(x: tap.x, y: tap.y)
            sleep(1)
            
            let afterHash = captureCurrentScreenHash()
            if afterHash != beforeHash && !afterHash.isEmpty {
                controller.captureUniqueScreenshot("detail_view")
                navigateBack()
                break
            }
        }
    }
    
    func exploreNavigationStack() {
        print("\n🗺️ Exploring navigation stack...")
        
        // Try to find and tap navigation items
        // Many apps have navigation items in the top area
        let navPositions = [
            (x: 50, y: 100),   // Top left (back button area)
            (x: 350, y: 100),  // Top right (menu/settings)
            (x: 200, y: 100),  // Top center (title area, sometimes tappable)
        ]
        
        for pos in navPositions {
            let beforeHash = captureCurrentScreenHash()
            controller.tap(x: pos.x, y: pos.y)
            sleep(1)
            
            let afterHash = captureCurrentScreenHash()
            if afterHash != beforeHash && !afterHash.isEmpty {
                controller.captureUniqueScreenshot("nav_item")
                navigateBack()
            }
        }
    }
    
    func navigateBack() {
        // Try multiple back navigation methods
        // Method 1: Top left back button
        controller.tap(x: 30, y: 60)
        sleep(1)
        
        // Method 2: Swipe from left edge (iOS back gesture)
        let deviceHeight = controller.deviceName.contains("iPad") ? 1366 : 852
        let centerY = deviceHeight / 2
        controller.shell("xcrun simctl io '\(controller.deviceName)' swipe 10 \(centerY) 100 \(centerY)")
        sleep(1)
    }
    
    
    // MARK: - URL List Generation
    
    func generateUrlList() {
        // List all captured screenshots and create a JSON file with their paths
        let fileManager = FileManager.default
        let outputDir = controller.outputDir
        
        do {
            let files = try fileManager.contentsOfDirectory(atPath: outputDir)
            let pngFiles = files.filter { $0.hasSuffix(".png") && $0 != "temp_screenshot.png" }
            let sortedFiles = pngFiles.sorted()
            
            // URLs will be populated by the upload script
            let urlsJson = "[]"
            
            let urlsPath = "\(outputDir)/urls.json"
            try urlsJson.write(toFile: urlsPath, atomically: true, encoding: .utf8)
            
            print("\nGenerated \(sortedFiles.count) screenshots")
            for file in sortedFiles {
                print("  - \(file)")
            }
        } catch {
            print("Error listing screenshots: \(error)")
        }
    }
}

// MARK: - Main

print("===========================================")
print("  Accessibility Explorer for iOS Apps")
print("===========================================\n")

let controller = SimulatorController(
    deviceName: Config.deviceName,
    bundleId: Config.bundleId,
    outputDir: Config.outputDir
)

let explorer = AppExplorer(
    controller: controller,
    credentials: Config.credentials
)

explorer.explore()

