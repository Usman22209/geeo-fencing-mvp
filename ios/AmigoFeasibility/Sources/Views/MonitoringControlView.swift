import SwiftUI

struct MonitoringControlView: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        Button(action: {
            vm.toggleMonitoring()
        }) {
            HStack {
                Spacer()
                Text(vm.uiState.buttonTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AmigoColors.textWhite)
                Spacer()
            }
            .frame(height: 56)
            .background(vm.uiState.buttonColor)
            .cornerRadius(12)
            .shadow(color: vm.uiState.buttonColor.opacity(0.35), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
