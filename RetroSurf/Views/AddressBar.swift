import SwiftUI

struct AddressBar: View {
    @Binding var address: String
    let onGo: () -> Void
    let theme: SkinTheme

    var body: some View {
        HStack(spacing: 8) {
            Text(theme.locationLabel)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(theme.labelForeground)

            TextField("retrosurf://…", text: $address)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.black)
                .padding(.horizontal, 6)
                .frame(height: max(theme.locationRowHeight - 8, 18))
                .background(SunkenField())
                .onSubmit {
                    onGo()
                }

            Button(action: onGo) {
                Text("Go")
                    .font(theme.buttonFont)
                    .foregroundColor(theme.buttonForeground)
                    .frame(minWidth: 34)
            }
            .buttonStyle(BevelButtonStyle(theme: theme))
        }
    }
}

struct SunkenField: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)

            Rectangle()
                .fill(Color(rgb: 0x808080))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 1)
                .padding(.top, 1)

            Rectangle()
                .fill(Color(rgb: 0x808080))
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
                .padding(.leading, 1)

            Rectangle()
                .fill(Color(rgb: 0xFFFFFF))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 1)
                .padding(.bottom, 1)

            Rectangle()
                .fill(Color(rgb: 0xFFFFFF))
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.vertical, 1)
                .padding(.trailing, 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color(rgb: 0x000000), lineWidth: 1)
        )
    }
}