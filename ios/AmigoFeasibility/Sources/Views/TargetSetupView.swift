import SwiftUI

struct TargetSetupView: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🎯 TARGET REMINDER LOCATION")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AmigoColors.textPrimary)

            // 3 Quick Target Buttons Row
            HStack(spacing: 6) {
                TargetQuickButton(
                    title: "📍 Here (0m)",
                    textColor: AmigoColors.accent
                ) {
                    vm.setTargetToCurrentLocation()
                }

                TargetQuickButton(
                    title: "🚶 60m Ahead",
                    textColor: AmigoColors.stateGreen
                ) {
                    vm.setTargetAhead(meters: 60.0)
                }

                TargetQuickButton(
                    title: "🚶 100m Ahead",
                    textColor: AmigoColors.stateGreen
                ) {
                    vm.setTargetAhead(meters: 100.0)
                }
            }
            .padding(.top, 4)

            // Lat & Lng Input Fields side-by-side
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latitude")
                        .font(.system(size: 10))
                        .foregroundColor(AmigoColors.textMuted)

                    TextField("Latitude", text: $vm.targetLatText)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(AmigoColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AmigoColors.inputBg)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AmigoColors.cardStroke, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Longitude")
                        .font(.system(size: 10))
                        .foregroundColor(AmigoColors.textMuted)

                    TextField("Longitude", text: $vm.targetLngText)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(AmigoColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AmigoColors.inputBg)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AmigoColors.cardStroke, lineWidth: 1)
                        )
                }
            }
            .padding(.top, 4)

            // Arm Radio Buttons & Save Target Row
            HStack(alignment: .center) {
                // Radio Group
                HStack(spacing: 12) {
                    ArmRadioButton(
                        label: "50m Arm",
                        isSelected: vm.activeArm == .arm50M
                    ) {
                        vm.setArm(.arm50M)
                    }

                    ArmRadioButton(
                        label: "150m Arm",
                        isSelected: vm.activeArm == .arm150M
                    ) {
                        vm.setArm(.arm150M)
                    }
                }

                Spacer()

                // Save Button
                Button(action: {
                    vm.saveTargetFromInputs()
                }) {
                    Text("💾 Save")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(AmigoColors.accent)
                        .foregroundColor(AmigoColors.textWhite)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 4)
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

struct TargetQuickButton: View {
    let title: String
    let textColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .background(AmigoColors.inputBg)
                .foregroundColor(textColor)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AmigoColors.cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ArmRadioButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? AmigoColors.accent : AmigoColors.textMuted, lineWidth: 2)
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Circle()
                            .fill(AmigoColors.accent)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(AmigoColors.textPrimary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
