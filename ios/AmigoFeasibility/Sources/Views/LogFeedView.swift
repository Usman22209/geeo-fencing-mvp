import SwiftUI

struct LogFeedView: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Row
            HStack {
                Text("LIVE TELEMETRY LOG")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: 0x94A3B8))

                Spacer()

                Text("\(vm.humanLogLines.count) events")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x64748B))
            }

            // Scrollable Log Box
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if vm.humanLogLines.isEmpty {
                            Text("[READY] Ready. Set target and tap START.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(AmigoColors.logText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(Array(vm.humanLogLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(colorForLine(line))
                                    .lineSpacing(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 180)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
                .onChange(of: vm.humanLogLines.count) { newCount in
                    if newCount > 0 {
                        withAnimation {
                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(AmigoColors.logBg)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }

    private func colorForLine(_ line: String) -> Color {
        if line.contains("CONFIRMED") || line.contains("🎉") || line.contains("✅") {
            return AmigoColors.stateGreen
        } else if line.contains("WAKE") || line.contains("🔔") || line.contains("⚡") {
            return AmigoColors.stateAmber
        } else if line.contains("DECISION") || line.contains("📡") {
            return AmigoColors.logText
        } else if line.contains("❌") || line.contains("failed") || line.contains("FAILED") {
            return AmigoColors.stateRed
        } else if line.contains("📝") || line.contains("Note") {
            return Color(hex: 0xC084FC) // Purple
        } else {
            return Color(hex: 0xE2E8F0)
        }
    }
}
