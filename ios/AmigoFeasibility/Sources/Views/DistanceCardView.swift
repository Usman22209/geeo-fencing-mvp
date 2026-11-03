import SwiftUI

struct DistanceCardView: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        VStack(spacing: 4) {
            Text("DISTANCE TO TARGET")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AmigoColors.textMuted)

            Text(vm.liveDistanceText)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundColor(vm.liveDistanceColor)
                .padding(.top, 2)

            Text(vm.liveStatusText)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(vm.liveStatusTextColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(vm.liveStatusBgColor)
                .cornerRadius(8)
                .padding(.top, 4)

            // Progress Bar Row matching Android lines 318-351
            HStack(alignment: .center, spacing: 8) {
                Text("Target (0m)")
                    .font(.system(size: 10))
                    .foregroundColor(AmigoColors.textMuted)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AmigoColors.stateGrayBg)
                            .frame(height: 8)

                        Capsule()
                            .fill(AmigoColors.stateGreen)
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(vm.liveProgress))), height: 8)
                    }
                }
                .frame(height: 8)

                Text(vm.fenceIndicatorText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AmigoColors.stateBlue)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(AmigoColors.cardBg)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AmigoColors.cardStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}
