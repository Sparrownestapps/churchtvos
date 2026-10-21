import SwiftUI
import ChurchTVCore

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Image(systemName: "tv.and.mediabox.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Church TV OS Remote").font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text("Control your church's TV screens from your phone.")
                        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .email).submitLabel(.next)
                        .onSubmit { focus = .password }
                        .padding(14).background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password).submitLabel(.go)
                        .onSubmit { signIn() }
                        .padding(14).background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))

                    if let e = model.signInError { Banner(text: e, style: .error) }

                    Button(action: signIn) {
                        Group {
                            if model.isSigningIn { ProgressView() } else { Text("Sign in").fontWeight(.semibold) }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.isSigningIn)

                    Button { Task { await model.startDemo() } } label: {
                        Label("Try the demo", systemImage: "sparkles").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                }
                .frame(maxWidth: 440)

                VStack(spacing: 10) {
                    Text("Use the same email and password as the website. New accounts are created on the website.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Link("Create an account on the website", destination: Config.websiteURL)
                    Link("Delete your account", destination: Config.deleteAccountURL)
                }
                .font(.subheadline)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func signIn() {
        focus = nil
        Task { await model.signIn(email: email, password: password) }
    }
}

struct ChurchPickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if model.churches.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No churches found").font(.headline)
                            Text(model.loadError ?? "Your account is not a member of any church yet. Ask a church admin to add your email on the website, then pull to refresh.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    Section("Choose a church") {
                        ForEach(model.churches) { c in
                            Button { Task { await model.choose(c) } } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(c.organization.name).font(.headline).foregroundStyle(.primary)
                                        Text("\(c.role.displayName) · \(c.modules.map(\.displayName).joined(separator: ", "))")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                }
            }
            .navigationTitle("Church TV OS")
            .refreshable { await model.loadChurches(autoSelect: false) }
        }
    }
}
