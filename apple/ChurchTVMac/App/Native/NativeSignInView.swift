import SwiftUI
import ChurchTVCore

/// Sign in with the same account as the website. The session lives in the Keychain (supabase-swift).
struct NativeSignInView: View {
    @Environment(MenuModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    private enum Field { case email, password }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "tv.and.mediabox").font(.system(size: 52)).foregroundStyle(.tint)
            Text("Church TV OS").font(.largeTitle.weight(.semibold))
            Text("Sign in with the same email and password as the website.").foregroundStyle(.secondary)
            VStack(spacing: 10) {
                TextField("Email", text: $email).textContentType(.username).focused($focus, equals: .email).onSubmit { focus = .password }
                SecureField("Password", text: $password).textContentType(.password).focused($focus, equals: .password).onSubmit(signIn)
                if let e = model.signInError { Text(e).font(.callout).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
                Button(action: signIn) {
                    HStack { if model.isSigningIn { ProgressView().controlSize(.small) }; Text("Sign in").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                .disabled(model.isSigningIn || email.isEmpty || password.isEmpty)
            }
            .textFieldStyle(.roundedBorder).frame(width: 320)
            Divider().frame(width: 320)
            HStack(spacing: 14) {
                Button("Try the demo") { Task { await model.setDemo(true) } }
                Link("Create an account on the website", destination: AppLinks.dashboard)
            }.buttonStyle(.link)
            Text("Demo mode shows a sample church with four TVs. No account needed.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.signInError = nil; focus = .email }
    }

    private func signIn() {
        guard !email.isEmpty, !password.isEmpty else { return }
        Task { await model.signIn(email: email, password: password) }
    }
}
