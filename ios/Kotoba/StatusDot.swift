import KotobaCore
import SwiftUI

/// The same dot as in the browser extension: filled when loaded, a ring when
/// released, pulsing while loading, red when the server cannot be used.
struct StatusDot: View {
    let status: ServerStatus

    @State private var dimmed = false

    var body: some View {
        Circle()
            .strokeBorder(status == .sleeping ? Color.secondary : .clear, lineWidth: 2)
            .background(Circle().fill(fill))
            .frame(width: 12, height: 12)
            .opacity(status == .loading && dimmed ? 0.25 : 1)
            .onChange(of: status, initial: true) {
                dimmed = false
                guard status == .loading else { return }
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) { dimmed = true }
            }
            .accessibilityElement()
            .accessibilityLabel(name)
            .accessibilityValue(status.rawValue)
            .accessibilityIdentifier("serverStatus")
    }

    private var fill: Color {
        switch status {
        case .ready: .accentColor
        case .sleeping: .clear
        case .loading: .orange
        case .unauthorized, .unreachable: .red
        }
    }

    private var name: String {
        switch status {
        case .ready: "モデル読み込み済み"
        case .sleeping: "モデル未読み込み"
        case .loading: "モデル読み込み中"
        case .unauthorized: "API キーが正しくありません"
        case .unreachable: "サーバーに接続できません"
        }
    }
}
