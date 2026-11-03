import SwiftUI

struct ContentView: View {
    @StateObject private var vm = MainViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // ========== TOP HEADER BAR (Android Lines 17-72) ==========
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AMIGO Feasibility Demo")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(AmigoColors.textWhite)

                        Text("Native iOS Proximity & Approach Engine")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0x94A3B8))
                    }

                    Spacer()

                    // State Badge Pill
                    Text(vm.uiState.label)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(vm.uiState.bgColor)
                        .foregroundColor(vm.uiState.textColor)
                        .cornerRadius(6)

                    // Battery Info
                    Text(vm.batteryText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: 0x94A3B8))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AmigoColors.primaryDark)

                // ========== SCROLLABLE CARDS CONTAINER ==========
                ScrollView {
                    VStack(spacing: 10) {
                        DemoGuideView(vm: vm)
                        DistanceCardView(vm: vm)
                        TargetSetupView(vm: vm)
                        MonitoringControlView(vm: vm)
                        QuickActionsView(vm: vm)
                        LogFeedView(vm: vm)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                .background(AmigoColors.background)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .background(AmigoColors.primaryDark.ignoresSafeArea(.all, edges: .top))

            // ========== ANDROID-STYLE FLOATING TOAST NOTIFICATION ==========
            if vm.showToast, let msg = vm.toastMessage {
                Text(msg)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AmigoColors.textWhite)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AmigoColors.primary.opacity(0.92))
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            vm.updateBatteryDisplay()
            vm.checkPermissions()
            vm.startLiveDistanceTracking()
        }
        .alert("Add Tester Note", isPresented: $vm.showNoteDialog) {
            TextField("e.g. notification seen on lock screen", text: $vm.noteInputText)
            Button("Save", action: { vm.addNote() })
            Button("Cancel", role: .cancel) { vm.noteInputText = "" }
        } message: {
            Text("Enter field observation to append to the JSONL log file:")
        }
        .alert("Permission & Restriction Status", isPresented: $vm.showPermissionsDialog) {
            Button("Settings") { PermissionHelper.openAppSettings() }
            Button("Close", role: .cancel) {}
        } message: {
            Text(vm.permissionsMessage)
        }
        .sheet(isPresented: $vm.showShareSheet) {
            if let url = vm.exportLogURL {
                ShareSheet(activityItems: [url])
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
