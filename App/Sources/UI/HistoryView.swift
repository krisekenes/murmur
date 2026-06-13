import SwiftUI

public struct HistoryView: View {
    @ObservedObject var state: AppState
    public init(state: AppState) { self.state = state }
    public var body: some View {
        Text("History").frame(width: 380, height: 480)
    }
}
