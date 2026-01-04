#!/usr/bin/env swift

import Foundation

// MARK: - Configuration

struct Config {
    static let deviceName = ProcessInfo.processInfo.environment["DEVICE_NAME"] ?? "iPhone 15 Pro Max"
    static let outputDir = ProcessInfo.processInfo.environment["OUTPUT_DIR"] ?? "screenshots"
    static let bundleId = ProcessInfo.processInfo.environment["BUNDLE_ID"] ?? ""
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

// MARK: - App Explorer

class AppExplorer {
    let controller: SimulatorController
    let credentials: Credentials?
    
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
    }
    
    // MARK: - Main Exploration Flow
    
    func explore() {
        print("\n🚀 Starting app exploration...")
        print("Device: \(controller.deviceName)")
        print("Bundle ID: \(controller.bundleId)")
        
        // Try to skip onboarding BEFORE launching
        attemptSkipOnboardingPreLaunch()
        
        // Launch the app (with skip arguments if needed)
        attemptLaunchWithSkipArgs()
        
        // Capture launch screen
        controller.captureUniqueScreenshot("launch")
        sleep(1)
        
        // Quick check if we're past onboarding
        let initialHash = captureCurrentScreenHash()
        
        // Try to skip onboarding if still present
        if !attemptSkipOnboardingPostLaunch() {
            // If skip failed, try to navigate through onboarding
            handleOnboarding()
        }
        
        // Handle login if needed
        handleLogin()
        
        // Use deep link if provided (can bypass onboarding)
        if let deepLink = credentials?.deepLink {
            controller.openDeepLink(deepLink)
            controller.captureUniqueScreenshot("deep_link")
            sleep(2)
        }
        
        // Explore main app systematically
        exploreTabs()
        exploreMainContent()
        exploreNavigationStack()
        
        // Generate URL list file
        generateUrlList()
        
        print("\n✅ Exploration complete!")
        print("Total unique screenshots: \(controller.screenshotCount)")
    }
    
    // MARK: - Onboarding Skip Methods
    
    func attemptSkipOnboardingPreLaunch() {
        print("\n🔧 Attempting to skip onboarding (pre-launch)...")
        
        // Method 1: Inject UserDefaults
        print("  → Injecting common UserDefaults keys...")
        controller.injectUserDefaults(onboardingUserDefaults)
        sleep(1)
    }
    
    func attemptLaunchWithSkipArgs() {
        // Try launching with skip arguments
        print("  → Launching with skip arguments...")
        for arg in skipOnboardingArgs {
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
        controller.launchApp()
    }
    
    func attemptSkipOnboardingPostLaunch() -> Bool {
        print("\n🔍 Checking if onboarding is present...")
        
        // Capture current screen
        controller.captureUniqueScreenshot("check_onboarding")
        
        // Try multiple skip methods
        // Method 1: Try skip button positions
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
        
        // Method 2: Try swiping through quickly
        print("  → Trying quick swipe through...")
        for _ in 0..<5 {
            controller.swipeLeft()
            usleep(500000)
            let hash = captureCurrentScreenHash()
            if !hash.isEmpty {
                controller.captureUniqueScreenshot("swipe_skip")
            }
        }
        
        // Method 3: Try custom skip button text if provided
        if let customSkip = credentials?.skipButtonText {
            print("  → Looking for custom skip: \(customSkip)")
            // Would need OCR/accessibility API here
        }
        
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
        print("\n📱 Checking for onboarding...")
        
        var onboardingScreens = 0
        let maxOnboardingScreens = 8
        
        while onboardingScreens < maxOnboardingScreens {
            // Capture current screen
            controller.captureUniqueScreenshot("onboarding_\(onboardingScreens)")
            
            // Try to advance onboarding
            // First, try tapping common "Next" button positions
            let nextButtonPositions = [
                (x: 200, y: 750),  // Bottom center iPhone
                (x: 350, y: 800),  // Bottom right iPhone
                (x: 512, y: 1200), // Bottom center iPad
            ]
            
            var advanced = false
            for pos in nextButtonPositions {
                controller.tap(x: pos.x, y: pos.y)
                sleep(1)
                
                // Check if screen changed (simplified check)
                advanced = true
                break
            }
            
            if !advanced {
                // Try swiping left
                controller.swipeLeft()
            }
            
            onboardingScreens += 1
            
            // Check for skip button or main content
            // In a real implementation, we'd use OCR or accessibility APIs
            sleep(1)
        }
        
        // Try to skip onboarding
        print("Trying to skip onboarding...")
        trySkipButtons()
    }
    
    func trySkipButtons() {
        // Try common skip button positions
        let skipPositions = [
            (x: 350, y: 50),   // Top right
            (x: 350, y: 100),  // Below status bar
            (x: 200, y: 800),  // Bottom center
            (x: 200, y: 750),  // Above bottom
        ]
        
        for pos in skipPositions {
            controller.tap(x: pos.x, y: pos.y)
            usleep(500000)
        }
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
    
    // MARK: - Tab Exploration
    
    func exploreTabs() {
        print("\n📑 Exploring tabs...")
        
        // Get device-specific tab bar Y position
        let tabBarY = controller.deviceName.contains("iPad") ? 1330 : 820
        
        // Try different numbers of tabs (most apps have 3-5)
        let deviceWidth = controller.deviceName.contains("iPad") ? 1024 : 393
        
        // Try 3, 4, and 5 tabs
        for tabCount in [3, 4, 5] {
            let tabSpacing = deviceWidth / tabCount
            
            for i in 0..<tabCount {
                let tabX = tabSpacing / 2 + (i * tabSpacing)
                
                print("Tapping tab \(i + 1) of \(tabCount) at position (\(tabX), \(tabBarY))")
                controller.tap(x: tabX, y: tabBarY)
                sleep(1)
                
                controller.captureUniqueScreenshot("tab_\(i + 1)")
                
                // Explore content within this tab
                exploreContentInCurrentView()
            }
        }
    }
    
    // MARK: - Main Content Exploration
    
    func exploreMainContent() {
        print("\n🔍 Exploring main content...")
        
        // Grid-based exploration - tap on a grid of positions
        let deviceWidth = controller.deviceName.contains("iPad") ? 1024 : 393
        let deviceHeight = controller.deviceName.contains("iPad") ? 1366 : 852
        
        // Create a 3x4 grid of tap positions
        let gridCols = 3
        let gridRows = 4
        let colSpacing = deviceWidth / (gridCols + 1)
        let rowSpacing = (deviceHeight - 200) / (gridRows + 1) // Leave space for tab bar
        
        for row in 0..<gridRows {
            for col in 0..<gridCols {
                let x = colSpacing * (col + 1)
                let y = 100 + (rowSpacing * (row + 1))
                
                print("Exploring grid position (\(col + 1), \(row + 1))")
                let beforeHash = captureCurrentScreenHash()
                
                controller.tap(x: x, y: y)
                sleep(1)
                
                let afterHash = captureCurrentScreenHash()
                if afterHash != beforeHash && !afterHash.isEmpty {
                    controller.captureUniqueScreenshot("grid_\(col + 1)_\(row + 1)")
                    
                    // Explore this new screen
                    exploreContentInCurrentView()
                    
                    // Navigate back
                    navigateBack()
                }
            }
        }
        
        // Scroll down and capture more content
        print("Scrolling to find more content...")
        for i in 0..<5 {
            controller.swipeDown()
            sleep(1)
            controller.captureUniqueScreenshot("scroll_\(i + 1)")
        }
        
        // Scroll up
        print("Scrolling up...")
        for i in 0..<3 {
            controller.swipeUp()
            sleep(1)
            controller.captureUniqueScreenshot("scroll_up_\(i + 1)")
        }
    }
    
    func exploreContentInCurrentView() {
        // Quick exploration of current view
        // Try tapping common interactive areas
        let quickTaps = [
            (x: 200, y: 300),
            (x: 200, y: 500),
            (x: 100, y: 400),
            (x: 300, y: 400)
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

