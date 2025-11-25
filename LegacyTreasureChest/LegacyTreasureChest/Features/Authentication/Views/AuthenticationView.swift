//
//  AuthenticationView.swift
//  LegacyTreasureChest
//
//  Sign in with Apple screen backed by AuthenticationViewModel.
//  Includes a simulator-only "Continue" button for development.
//

import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    
    @StateObject private var viewModel: AuthenticationViewModel
    
    // MARK: - Init
    
    init(viewModel: AuthenticationViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                
                Text("Legacy Treasure Chest")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                
                Text("Sign in to start capturing your items and stories.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // MARK: - Real Sign in with Apple button
                SignInWithAppleButton(.signIn) { request in
                    // No configuration needed for now.
                } onCompletion: { result in
                    // We still trigger sign-in via onTapGesture.
                }
                .frame(height: 45)
                .onTapGesture {
                    Task {
                        await viewModel.signIn()
                    }
                }
                .disabled(viewModel.isBusy)
                .opacity(viewModel.isBusy ? 0.6 : 1.0)
                .padding(.horizontal, 40)

                // MARK: - Simulator-only dev override
                #if targetEnvironment(simulator)
                Button(action: {
                    viewModel.isSignedIn = true
                }) {
                    Text("Continue in Simulator")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 40)
                .padding(.top, 4)
                #endif

            }
        }
    }
}


#Preview {
    let service = PreviewAuthService()
    let vm = AuthenticationViewModel(authService: service)
    return AuthenticationView(viewModel: vm)
}
