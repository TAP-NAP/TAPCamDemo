import SwiftUI

struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ForEach(0..<8) { _ in
                    Text(verbatim: "test name")
                        .font(.system(.title2, design: .serif))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
