import SwiftUI

struct QuickActionsView: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        HStack(spacing: 5) {
            QuickActionButton(title: "⚡ 60s Burst") {
                vm.triggerManualBurstTest()
            }

            QuickActionButton(title: "📤 Export") {
                vm.exportLogs()
            }

            QuickActionButton(title: "📝 Note") {
                vm.showNoteDialog = true
            }

            QuickActionButton(title: "⚙️ Perms") {
                vm.showPermissionsStatus()
            }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
                .background(AmigoColors.inputBg)
                .foregroundColor(AmigoColors.textPrimary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AmigoColors.cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
