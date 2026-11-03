import SwiftUI

struct DemoGuideView: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        VStack(spacing: 10) {
            // Permission Warning Banner (Hidden when all granted)
            if let title = vm.permissionWarningTitle, let desc = vm.permissionWarningDesc {
                HStack(alignment: .center, spacing: 10) {
                    Text("⚠️")
                        .font(.system(size: 20))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AmigoColors.textPrimary)
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundColor(AmigoColors.textSecondary)
                    }

                    Spacer()

                    Button(action: {
                        if !PermissionHelper.hasFineLocation() {
                            PermissionHelper.shared.requestPermissions()
                        } else if !PermissionHelper.hasAlwaysLocation() {
                            PermissionHelper.openAppSettings()
                        } else {
                            PermissionHelper.shared.requestNotificationAuthorization()
                        }
                    }) {
                        Text("Fix Now")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AmigoColors.stateAmber)
                            .foregroundColor(AmigoColors.textWhite)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AmigoColors.stateAmberBg)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AmigoColors.stateAmber, lineWidth: 1)
                )
            }

            // How-To-Demo Collapsible Card
            VStack(alignment: .leading, spacing: 0) {
                // Header (Tappable)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.isGuideExpanded.toggle()
                    }
                }) {
                    HStack {
                        Text("💡 HOW TO RUN THIS TEST DEMO")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AmigoColors.textPrimary)

                        Spacer()

                        Text(vm.isGuideExpanded ? "Hide ▲" : "Show ▼")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AmigoColors.accent)
                    }
                }
                .buttonStyle(PlainButtonStyle())

                if vm.isGuideExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1️⃣ Set Target: Tap '📍 Here' to make your current spot the reminder target, OR tap '🚶 60m Ahead'.\n2️⃣ Start Test: Tap ▶ START MONITORING below. Turn off / lock the phone.\n3️⃣ Walk Test: Walk away past 60m, then walk toward the target. When approaching within 40m, your phone will ring and show the Opportunity notification!")
                            .font(.system(size: 11.5))
                            .foregroundColor(AmigoColors.textSecondary)
                            .lineSpacing(3)
                            .padding(.top, 8)

                        Text("Select Test Case to Log:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AmigoColors.textMuted)
                            .padding(.top, 4)

                        // 3 Scenario Buttons Row
                        HStack(spacing: 6) {
                            ScenarioPill(
                                title: "✓ Positive Approach",
                                isSelected: vm.selectedScenario.contains("Positive")
                            ) {
                                vm.setScenario("Positive Approach")
                            }

                            ScenarioPill(
                                title: "Neg A (Stationary)",
                                isSelected: vm.selectedScenario.contains("Stationary")
                            ) {
                                vm.setScenario("Negative A (Stationary)")
                            }

                            ScenarioPill(
                                title: "Neg B (Outside 40m)",
                                isSelected: vm.selectedScenario.contains("Outside")
                            ) {
                                vm.setScenario("Negative B (Outside 40m)")
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(AmigoColors.cardBg)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AmigoColors.cardStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
    }
}

struct ScenarioPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .padding(.horizontal, 2)
                .background(isSelected ? AmigoColors.accent : AmigoColors.inputBg)
                .foregroundColor(isSelected ? AmigoColors.textWhite : AmigoColors.textPrimary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? AmigoColors.accent : AmigoColors.cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
