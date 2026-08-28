//
//  ContentView.swift
//  App-Block
//
//  Clean, minimalist SwiftUI interface for Focus Time Screen Time POC.
//

import SwiftUI
import FamilyControls
import ManagedSettings

struct ContentView: View {
    @StateObject private var focusManager = FocusManager.shared
    @State private var isPickerPresented = false
    @State private var showingInfoSheet = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Permission Status Banner
                permissionBanner
                
                ScrollView {
                    VStack(spacing: 28) {
                        // Hero Status
                        statusHero
                        
                        // Mode Switcher (Allowlist vs Blocklist)
                        modePicker
                        
                        // App List & Configuration
                        appsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                }
                
                // Bottom Primary Action
                actionButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingInfoSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .familyActivityPicker(
                isPresented: $isPickerPresented,
                selection: $focusManager.selection
            )
            .sheet(isPresented: $showingInfoSheet) {
                InfoSheet()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                focusManager.refreshAuthorizationStatus()
            }
        }
    }
    
    // MARK: - Permission Status Banner
    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(permissionStatusColor)
                .frame(width: 8, height: 8)
            
            Text("Screen Time:")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(permissionStatusTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(permissionStatusColor)
            
            Spacer()
            
            if focusManager.authorizationStatus != .approved {
                Button {
                    if focusManager.authorizationStatus == .denied {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        Task {
                            try? await focusManager.requestAuthorization()
                        }
                    }
                } label: {
                    Text(focusManager.authorizationStatus == .denied ? "Open Settings" : "Authorize")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(permissionStatusColor.opacity(0.12)))
                        .foregroundStyle(permissionStatusColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(uiColor: .secondarySystemBackground))
    }
    
    private var permissionStatusTitle: String {
        switch focusManager.authorizationStatus {
        case .approved:
            return "Approved"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Setup Required"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var permissionStatusColor: Color {
        switch focusManager.authorizationStatus {
        case .approved:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .secondary
        }
    }
    
    // MARK: - Status Hero
    private var statusHero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(focusManager.isFocusActive ? Color.green.opacity(0.12) : Color(uiColor: .secondarySystemBackground))
                    .frame(width: 88, height: 88)
                
                Image(systemName: focusManager.isFocusActive ? "moon.stars.fill" : (focusManager.mode == .allowlist ? "shield.fill" : "hand.raised.fill"))
                    .font(.system(size: 36))
                    .foregroundStyle(focusManager.isFocusActive ? Color.green : Color.secondary)
            }
            
            VStack(spacing: 4) {
                Text(focusManager.isFocusActive ? "Focusing" : "Ready")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(statusSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var statusSubtitle: String {
        if focusManager.isFocusActive {
            return focusManager.mode == .allowlist ?
                "Allowlist active • All else blocked" :
                "Blocklist active • Selected apps blocked"
        } else {
            return focusManager.mode == .allowlist ?
                "Blocks all apps except allowed items" :
                "Blocks only selected distractions"
        }
    }
    
    // MARK: - Mode Picker
    private var modePicker: some View {
        Picker("Mode", selection: $focusManager.mode) {
            ForEach(FocusMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(focusManager.isFocusActive)
    }
    
    // MARK: - Apps Section
    private var appsSection: some View {
        VStack(spacing: 0) {
            // Header Row: Tap to open Apple's picker
            Button {
                isPickerPresented = true
            } label: {
                HStack {
                    Text(focusManager.mode == .allowlist ? "Allowed Apps" : "Blocked Apps")
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Text(focusManager.totalSelectedCount > 0 ? "\(focusManager.totalSelectedCount)" : "None")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .disabled(focusManager.isFocusActive)
            
            // App List (if any selected)
            if focusManager.hasSelection {
                Divider()
                    .padding(.leading, 16)
                
                VStack(spacing: 0) {
                    ForEach(Array(focusManager.selection.applicationTokens), id: \.self) { token in
                        itemRow(token: token) {
                            focusManager.remove(application: token)
                        }
                    }
                    ForEach(Array(focusManager.selection.categoryTokens), id: \.self) { catToken in
                        itemRow(catToken: catToken) {
                            focusManager.remove(category: catToken)
                        }
                    }
                    ForEach(Array(focusManager.selection.webDomainTokens), id: \.self) { webToken in
                        itemRow(webToken: webToken) {
                            focusManager.remove(webDomain: webToken)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
    
    // MARK: - Item Row
    private func itemRow(token: ApplicationToken, onRemove: @escaping () -> Void) -> some View {
        HStack {
            Label(token)
                .font(.subheadline)
                .lineLimit(1)
            
            Spacer()
            
            if !focusManager.isFocusActive {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private func itemRow(catToken: ActivityCategoryToken, onRemove: @escaping () -> Void) -> some View {
        HStack {
            Label(catToken)
                .font(.subheadline)
                .lineLimit(1)
            
            Spacer()
            
            if !focusManager.isFocusActive {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private func itemRow(webToken: WebDomainToken, onRemove: @escaping () -> Void) -> some View {
        HStack {
            Label(webToken)
                .font(.subheadline)
                .lineLimit(1)
            
            Spacer()
            
            if !focusManager.isFocusActive {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Action Button
    private var actionButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: focusManager.isFocusActive ? .medium : .heavy).impactOccurred()
            focusManager.toggleFocus()
        } label: {
            Text(focusManager.isFocusActive ? "Stop Focus" : "Start Focus")
                .font(.body)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(focusManager.isFocusActive ? Color.red : Color.primary)
                .foregroundStyle(focusManager.isFocusActive ? Color.white : Color(uiColor: .systemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info Sheet
struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Modes")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allowlist Mode")
                            .font(.headline)
                        Text("Shields all apps on your device except those explicitly selected.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Blocklist Mode")
                            .font(.headline)
                        Text("Shields only the selected apps, leaving all other apps accessible.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                
                Section(header: Text("System Exclusions")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why are some apps not blocked?")
                            .font(.headline)
                        Text("Apps in iOS Settings > Screen Time > Always Allowed (e.g. Messages, WhatsApp, Maps) have system immunity and bypass all third-party shields.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
