import SwiftUI

public struct SettingsView: View {
    @ObservedObject var state: AppState
    public init(state: AppState) { self.state = state }
    public var body: some View {
        Text("Settings").frame(width: 420, height: 320)
    }
}
