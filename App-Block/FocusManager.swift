//
//  FocusManager.swift
//  App-Block
//
//  A standalone, exportable Screen Time manager for iOS.
//  Encapsulates Apple's FamilyControls and ManagedSettings frameworks.
//

import Foundation
import Combine
import FamilyControls
import ManagedSettings

// MARK: - Focus Mode
public enum FocusMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case allowlist
    case blocklist
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .allowlist: return "Allowlist"
        case .blocklist: return "Blocklist"
        }
    }
}

// MARK: - Focus Manager
@MainActor
public final class FocusManager: ObservableObject {
    public static let shared = FocusManager()
    
    // MARK: - Published State
    @Published public private(set) var authorizationStatus: AuthorizationStatus = .notDetermined
    @Published public private(set) var isFocusActive: Bool = false
    
    @Published public var mode: FocusMode = .allowlist {
        didSet {
            guard mode != oldValue else { return }
            saveSelection(for: oldValue)
            persistMode()
            loadSelection(for: mode)
        }
    }
    
    @Published public var selection = FamilyActivitySelection() {
        didSet {
            saveSelection(for: mode)
        }
    }
    
    // Backward-compatibility alias
    public var activitySelection: FamilyActivitySelection {
        get { selection }
        set { selection = newValue }
    }
    
    // MARK: - Private Properties
    private let managedSettingsStore: ManagedSettingsStore
    private let modeStorageKey: String
    private let storageKeyPrefix: String
    
    // MARK: - Initializer
    public init(storeName: String = "FocusTimeStore") {
        self.managedSettingsStore = ManagedSettingsStore(named: .init(storeName))
        self.modeStorageKey = "\(storeName)_SelectedMode"
        self.storageKeyPrefix = "\(storeName)_Selection_"
        
        self.authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        
        if let savedMode = UserDefaults.standard.string(forKey: modeStorageKey),
           let parsedMode = FocusMode(rawValue: savedMode) {
            self.mode = parsedMode
        }
        
        loadSelection(for: self.mode)
    }
    
    // MARK: - Authorization
    public func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        refreshAuthorizationStatus()
    }
    
    public func refreshAuthorizationStatus() {
        self.authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    }
    
    // MARK: - Focus Control
    public func toggleFocus() {
        if isFocusActive {
            stopFocus()
        } else {
            startFocus()
        }
    }
    
    public func startFocus() {
        guard !isFocusActive else { return }
        
        let appTokens = selection.applicationTokens
        let categoryTokens = selection.categoryTokens
        let webTokens = selection.webDomainTokens
        
        switch mode {
        case .allowlist:
            // Allowlist: Shield ALL application categories EXCEPT chosen apps
            managedSettingsStore.shield.applications = nil
            managedSettingsStore.shield.applicationCategories = .all(except: appTokens)
            if !webTokens.isEmpty {
                managedSettingsStore.shield.webDomainCategories = .all(except: webTokens)
            } else {
                managedSettingsStore.shield.webDomainCategories = nil
            }
            managedSettingsStore.shield.webDomains = nil
            
        case .blocklist:
            // Blocklist: Shield ONLY chosen apps, categories, and web domains
            managedSettingsStore.shield.applications = appTokens.isEmpty ? nil : appTokens
            managedSettingsStore.shield.applicationCategories = categoryTokens.isEmpty ? nil : .specific(categoryTokens)
            managedSettingsStore.shield.webDomains = webTokens.isEmpty ? nil : webTokens
            managedSettingsStore.shield.webDomainCategories = nil
        }
        
        isFocusActive = true
    }
    
    public func stopFocus() {
        guard isFocusActive else { return }
        
        managedSettingsStore.clearAllSettings()
        managedSettingsStore.shield.applicationCategories = nil
        managedSettingsStore.shield.webDomainCategories = nil
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.webDomains = nil
        
        isFocusActive = false
    }
    
    // MARK: - Item Management
    public func remove(application token: ApplicationToken) {
        selection.applicationTokens.remove(token)
    }
    
    public func remove(category token: ActivityCategoryToken) {
        selection.categoryTokens.remove(token)
    }
    
    public func remove(webDomain token: WebDomainToken) {
        selection.webDomainTokens.remove(token)
    }
    
    public func clearSelection() {
        selection = FamilyActivitySelection()
    }
    
    // MARK: - Selection Inspectability
    public var hasSelection: Bool {
        !selection.applicationTokens.isEmpty ||
        !selection.categoryTokens.isEmpty ||
        !selection.webDomainTokens.isEmpty
    }
    
    public var totalSelectedCount: Int {
        selection.applicationTokens.count +
        selection.categoryTokens.count +
        selection.webDomainTokens.count
    }
    
    // MARK: - Persistence
    private func persistMode() {
        UserDefaults.standard.set(mode.rawValue, forKey: modeStorageKey)
    }
    
    private func saveSelection(for targetMode: FocusMode) {
        let key = storageKeyPrefix + targetMode.rawValue
        do {
            let data = try PropertyListEncoder().encode(selection)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("[FocusManager] Failed to encode FamilyActivitySelection: \(error)")
        }
    }
    
    private func loadSelection(for targetMode: FocusMode) {
        let key = storageKeyPrefix + targetMode.rawValue
        if let data = UserDefaults.standard.data(forKey: key) {
            do {
                let decoded = try PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
                self.selection = decoded
                return
            } catch {
                print("[FocusManager] Failed to decode FamilyActivitySelection for \(targetMode): \(error)")
            }
        }
        self.selection = FamilyActivitySelection()
    }
}
