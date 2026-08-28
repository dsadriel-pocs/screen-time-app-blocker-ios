# Apple Screen Time Frameworks — "Focus Time" POC

A clean, production-ready Proof of Concept (POC) demonstrating how to implement **Focus Mode app blocking** using Apple's official Screen Time APIs (**FamilyControls** and **ManagedSettings**).

---

## Table of Contents
- [Overview](#overview)
- [Frameworks Used](#frameworks-used)
- [How It Works](#how-it-works)
  - [1. Authorization (`FamilyControls`)](#1-authorization-familycontrols)
  - [2. App Selection (`FamilyActivityPicker`)](#2-app-selection-familyactivitypicker)
  - [3. Shielding Strategies (`ManagedSettings`)](#3-shielding-strategies-managedsettings)
    - [Allowlist (Whitelist)](#a-allowlist-mode-strict)
    - [Blocklist (Blacklist)](#b-blocklist-mode-selective)
  - [4. Displaying Apps (`Label(token)`)](#4-displaying-apps-securely)
  - [5. Ending a Session](#5-ending-a-session)
- [Project Configuration & Entitlements](#project-configuration--entitlements)
- [Simulator vs. Physical Device](#simulator-vs-physical-device)
- [How Screen Time Affects Notifications](#how-screen-time-affects-notifications)
- [Troubleshooting & Gotchas](#troubleshooting--gotchas)
- [Exporting `FocusManager.swift` to Other Projects](#exporting-focusmanagerswift-to-other-projects)
- [Project Structure](#project-structure)

---

## Overview

This POC allows users to:
1. Choose between **Allowlist** (block all apps except allowed ones) and **Blocklist** (block only selected distracting apps).
2. Select target apps, categories, and websites using Apple's native system sheet.
3. View a clean, Apple-native visual list of the selected items with authentic app icons and titles.
4. **Start/Stop Focus Time** with a single tap, enforcing system shields and tracking session time.

---

## Frameworks Used

| Framework | Role | Key APIs Used |
| :--- | :--- | :--- |
| **`FamilyControls`** | Permissions & App Picker | `AuthorizationCenter`, `FamilyActivityPicker`, `FamilyActivitySelection` |
| **`ManagedSettings`** | System Shielding & Policy Enforcement | `ManagedSettingsStore`, `ShieldSettings.ActivityCategoryPolicy`, `ApplicationToken` |
| **`SwiftUI`** | User Interface & Token Views | `Label(_ token: ApplicationToken)`, `.familyActivityPicker()` |

---

## How It Works

### 1. Authorization (`FamilyControls`)
Before accessing Screen Time capabilities, the app must request user authorization:

```swift
import FamilyControls

do {
    // Requests authorization for the user's personal device (iOS 16+)
    try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
} catch {
    print("Screen Time authorization failed: \(error)")
}
```

> **Note:** `.individual` requests authorization on the user's personal device without requiring iCloud Family Sharing parental controls.

---

### 2. App Selection (`FamilyActivityPicker`)
Apple protects user privacy by **never exposing raw bundle identifiers** or app usage history to third-party apps. Instead, apps are selected via Apple's secure system sheet:

```swift
import SwiftUI
import FamilyControls

struct ContentView: View {
    @State private var isPickerPresented = false
    @State private var activitySelection = FamilyActivitySelection()

    var body: some View {
        Button("Select Apps") {
            isPickerPresented = true
        }
        .familyActivityPicker(
            isPresented: $isPickerPresented,
            selection: $activitySelection
        )
    }
}
```

`FamilyActivitySelection` contains:
- `applicationTokens: Set<ApplicationToken>`
- `categoryTokens: Set<ActivityCategoryToken>`
- `webDomainTokens: Set<WebDomainToken>`

These tokens are **opaque**: your app cannot inspect their names or bundle IDs directly.

---

### 3. Shielding Strategies (`ManagedSettings`)

Shielding is controlled via `ManagedSettingsStore`. We initialize a named store for reliable persistence:

```swift
import ManagedSettings

let store = ManagedSettingsStore(named: .init("FocusTimeStore"))
```

#### A. Allowlist Mode (Strict)
Blocks **all application categories** on the device, exempting only the chosen tokens:

```swift
// 1. Clear any specific application shields
store.shield.applications = nil

// 2. Shield ALL categories EXCEPT the allowed application tokens
store.shield.applicationCategories = .all(except: activitySelection.applicationTokens)

// 3. Shield web domain categories if specified
if !activitySelection.webDomainTokens.isEmpty {
    store.shield.webDomainCategories = .all(except: activitySelection.webDomainTokens)
}
```

#### B. Blocklist Mode (Selective)
Shields **only** the selected apps, categories, and websites, keeping everything else unlocked:

```swift
let appTokens = activitySelection.applicationTokens
let categoryTokens = activitySelection.categoryTokens
let webTokens = activitySelection.webDomainTokens

// 1. Shield only the chosen apps
store.shield.applications = appTokens.isEmpty ? nil : appTokens

// 2. Shield only the chosen categories
store.shield.applicationCategories = categoryTokens.isEmpty ? nil : .specific(categoryTokens)

// 3. Shield only the chosen web domains
store.shield.webDomains = webTokens.isEmpty ? nil : webTokens
```

---

### 4. Displaying Apps Securely

Because `ApplicationToken` is opaque, Apple provides a native SwiftUI `Label` initializer that renders the app's authentic icon and display name without leaking its bundle ID:

```swift
ForEach(Array(activitySelection.applicationTokens), id: \.self) { token in
    Label(token) // Renders the app icon and name
}

ForEach(Array(activitySelection.categoryTokens), id: \.self) { token in
    Label(token) // Renders category icon and name (e.g. Social, Games)
}
```

---

### 5. Ending a Session

When the user stops Focus Time, all shields are cleared:

```swift
store.clearAllSettings()
store.shield.applicationCategories = nil
store.shield.webDomainCategories = nil
store.shield.applications = nil
store.shield.webDomains = nil
```

---

## Project Configuration & Entitlements

To use `FamilyControls` in an iOS app:

1. **Create an `.entitlements` file** (`App-Block/App-Block.entitlements`):
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>com.apple.developer.family-controls</key>
       <true/>
   </dict>
   </plist>
   ```

2. **Link Entitlements in Xcode**:
   In your target's Build Settings:
   - `CODE_SIGN_ENTITLEMENTS = "App-Block/App-Block.entitlements"`

---

## Simulator vs. Physical Device

| Feature | iOS Simulator | Physical iPhone |
| :--- | :--- | :--- |
| **SwiftUI UI & State Flow** | Supported | Supported |
| **Token Serialization (`UserDefaults`)** | Supported | Supported |
| **System App Shielding Overlay** | Limited / Mocked | **Fully Functional** |
| **Third-Party Installed Apps** | Not Available | **Fully Available** |

> **Recommendation:** To observe real system shields appearing over third-party apps (e.g., Instagram, YouTube, Slack), run the app on a **physical device** signed with your Apple Developer Team profile.

---

## How Screen Time Affects Notifications

When an application is shielded by `ManagedSettingsStore`, iOS alters how notifications are handled for that app:

| Notification Behavior | What Happens While Shielded |
| :--- | :--- |
| **Banners & Sounds** | **Suppressed.** iOS silences incoming banners, alert sounds, and lock screen alerts for shielded apps. |
| **Notification Center** | Notifications are held back or silenced while the shield is active. |
| **Tapping Existing Alerts** | If a notification was already in the Notification Center before the session started, tapping it **will not launch the app**—iOS presents the Screen Time shield instead. |
| **App Icon Badges** | Red unread badge counts on the app icon are suppressed while shielded. |
| **Session End** | As soon as Focus Time stops (`store.clearAllSettings()`), the shields lift and queued notifications deliver normally. |

### Screen Time Shielding vs. iOS Focus Modes (Do Not Disturb)

- **Screen Time (`ManagedSettings`)**: Imposes a **hard block** on app access (blocking app launches with a full-screen system shield) and automatically silences notifications for the shielded apps.
- **iOS Focus Modes**: Primarily **filters notification alerts and sounds**, but leaves the user free to open and use the app.

> **System Immunity ("Always Allowed"):** Apps listed in **iOS Settings > Screen Time > Always Allowed** (such as Phone, Messages, or user-whitelisted apps) have system immunity. Their notifications will continue to alert normally and will never be shielded.

---

## Troubleshooting & Gotchas

### 1. Why are some apps not blocked? (WhatsApp, Gmail, Uber, Messages)
Check **iOS Settings > Screen Time > Always Allowed**:
- Apple gives the system's **"Always Allowed"** list higher priority than any third-party app shield or `ManagedSettingsStore` setting.
- If an app is on that list, iOS will **never** display a shield over it.
- **Solution:** Remove the app from **Settings > Screen Time > Always Allowed**.

### 2. App was already open in memory
- If an app was active or suspended in the background before starting Focus Time, iOS's `managedsettingsd` daemon may delay presenting the shield.
- **Solution:** Swipe up from the App Switcher to quit the app, then tap it on the Home Screen. The shield will appear immediately.

### 3. Persisting `FamilyActivitySelection`
`FamilyActivitySelection` cannot be stored directly as raw JSON with `JSONEncoder`. Instead, use `PropertyListEncoder`:
```swift
// Saving
let data = try PropertyListEncoder().encode(selection)
UserDefaults.standard.set(data, forKey: "savedSelection")

// Loading
if let data = UserDefaults.standard.data(forKey: "savedSelection") {
    let selection = try PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
}
```

---

## Exporting `FocusManager.swift` to Other Projects

`FocusManager.swift` was designed to be **completely standalone, decoupled from UI code, and portable**. 

To use it in another iOS app:

1. **Copy `FocusManager.swift`** into your project.
2. **Add the entitlement**: Add `com.apple.developer.family-controls` (`<true/>`) to your app's `.entitlements` file.
3. **Use in your app**:

```swift
import SwiftUI
import FamilyControls

struct MyCustomFocusView: View {
    @StateObject private var focus = FocusManager.shared
    @State private var isPickerPresented = false

    var body: some View {
        VStack {
            // Mode selector
            Picker("Mode", selection: $focus.mode) {
                Text("Allowlist").tag(FocusMode.allowlist)
                Text("Blocklist").tag(FocusMode.blocklist)
            }
            .pickerStyle(.segmented)

            // Button to choose apps
            Button("Configure Apps (\(focus.totalSelectedCount))") {
                isPickerPresented = true
            }

            // Start / Stop
            Button(focus.isFocusActive ? "Stop" : "Start") {
                focus.toggleFocus()
            }
        }
        .familyActivityPicker(
            isPresented: $isPickerPresented,
            selection: $focus.selection
        )
    }
}
```

---

## Project Structure

```
App-Block/
├── App-Block/
│   ├── App_BlockApp.swift       # Main SwiftUI app entry point
│   ├── ContentView.swift         # Minimalist UI (Hero, Mode Picker, App List, Action Button)
│   ├── FocusManager.swift        # Standalone, exportable Screen Time service
│   ├── App-Block.entitlements    # FamilyControls capability entitlement
│   └── Assets.xcassets/          # App icons & color assets
├── App-Block.xcodeproj           # Xcode project file
└── README.md                     # Framework documentation & export guide
```
