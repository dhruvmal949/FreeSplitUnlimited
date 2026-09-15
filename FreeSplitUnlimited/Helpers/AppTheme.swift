//
//  AppTheme.swift
//  FreeSplitUnlimited
//

import SwiftUI
import UIKit

enum AppTheme {
    static let teal = Color(red: 42 / 255, green: 157 / 255, blue: 143 / 255)
    static let deepTeal = Color(red: 18 / 255, green: 94 / 255, blue: 92 / 255)
    static let brightTeal = Color(red: 64 / 255, green: 186 / 255, blue: 168 / 255)
    static let softMint = Color(red: 182 / 255, green: 226 / 255, blue: 216 / 255)
    static let lightAqua = Color(red: 224 / 255, green: 242 / 255, blue: 236 / 255)
    static let softSky = Color(red: 210 / 255, green: 232 / 255, blue: 240 / 255)
    static let seaFoam = Color(red: 150 / 255, green: 210 / 255, blue: 198 / 255)
    static let paleGold = Color(red: 240 / 255, green: 220 / 255, blue: 170 / 255)
    /// Money you still need to pay.
    static let youOwe = Color(red: 227 / 255, green: 56 / 255, blue: 53 / 255)
    /// Money others still need to pay you.
    static let youAreOwed = Color(red: 22 / 255, green: 148 / 255, blue: 74 / 255)

    static func balanceColor(for net: Decimal) -> Color {
        if net > 0 { return youAreOwed }
        if net < 0 { return youOwe }
        return .secondary
    }

    /// Height of the custom Friends / Groups / Notifications / Settings bar,
    /// not counting the home indicator.
    static let mainTabBarHeight: CGFloat = 56

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                softMint,
                lightAqua,
                seaFoam.opacity(0.55),
                softSky,
                teal.opacity(0.35)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var heroCardGradient: LinearGradient {
        LinearGradient(
            colors: [
                teal.opacity(0.35),
                brightTeal.opacity(0.22),
                Color.white.opacity(0.55)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct ThemedBackground: View {
    var body: some View {
        ZStack {
            // Base wash
            AppTheme.backgroundGradient

            // Soft radial glow behind content
            RadialGradient(
                colors: [
                    Color.white.opacity(0.55),
                    AppTheme.lightAqua.opacity(0.2),
                    .clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 420
            )
            .blendMode(.screen)

            // Soft color orbs (static)
            orb(color: AppTheme.teal.opacity(0.30), size: 340, x: -150, y: -260, blur: 22)
            orb(color: AppTheme.brightTeal.opacity(0.24), size: 260, x: 160, y: -120, blur: 26)
            orb(color: AppTheme.deepTeal.opacity(0.16), size: 320, x: 140, y: 300, blur: 30)
            orb(color: AppTheme.paleGold.opacity(0.18), size: 200, x: -110, y: 180, blur: 24)
            orb(color: Color.white.opacity(0.35), size: 170, x: 40, y: -20, blur: 18)

            // Split / sharing motif: soft rings
            shareRings
                .opacity(0.22)
                .offset(x: 110, y: -210)

            shareRings
                .opacity(0.14)
                .offset(x: -130, y: 260)

            // Bottom wave band
            WaveShape()
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.teal.opacity(0.18),
                            AppTheme.deepTeal.opacity(0.10),
                            .clear
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(height: 220)
                .frame(maxHeight: .infinity, alignment: .bottom)

            // Subtle diagonal sheen
            LinearGradient(
                colors: [
                    .clear,
                    Color.white.opacity(0.18),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.softLight)
        }
        .ignoresSafeArea()
    }

    private func orb(color: Color, size: CGFloat, x: CGFloat = 0, y: CGFloat = 0, blur: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: blur)
            .offset(x: x, y: y)
    }

    private var shareRings: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.deepTeal.opacity(0.35), lineWidth: 1.5)
                .frame(width: 120, height: 120)
            Circle()
                .stroke(AppTheme.teal.opacity(0.28), lineWidth: 1.2)
                .frame(width: 86, height: 86)
            Circle()
                .fill(AppTheme.teal.opacity(0.12))
                .frame(width: 36, height: 36)

            Image(systemName: "dollarsign")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.deepTeal.opacity(0.35))
        }
    }
}

private struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.height * 0.35
        path.move(to: CGPoint(x: 0, y: midY))
        path.addCurve(
            to: CGPoint(x: rect.width, y: midY * 0.8),
            control1: CGPoint(x: rect.width * 0.28, y: midY - 40),
            control2: CGPoint(x: rect.width * 0.68, y: midY + 50)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

extension View {
    func freeSplitBackground() -> some View {
        self.background {
            ThemedBackground()
        }
    }

    func freeSplitListStyle() -> some View {
        self
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .contentMargins(.bottom, 12, for: .scrollContent)
    }

    /// Pushed screens do not inherit the tab bar’s `safeAreaInset`, so lists
    /// extend under it and cannot scroll the last rows into view.
    func avoidsMainTabBar() -> some View {
        self.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: AppTheme.mainTabBarHeight)
                .accessibilityHidden(true)
        }
    }

    func keyboardDoneButton() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .accessibilityIdentifier("keyboardDone")
            }
        }
    }
}

struct NoneState: View {
    var image: String
    var message: String

    var body: some View {
        ContentUnavailableView("None", systemImage: image, description: Text(message))
    }
}

private struct PopToHomeKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var popToHome: () -> Void {
        get { self[PopToHomeKey.self] }
        set { self[PopToHomeKey.self] = newValue }
    }
}

struct HomeBackButton: View {
    @Environment(\.popToHome) private var popToHome

    var body: some View {
        Button(action: popToHome) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                Text("Home")
            }
        }
        .accessibilityLabel("Back to Home")
    }
}

extension View {
    func homeBackButton() -> some View {
        self
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HomeBackButton()
                }
            }
    }
}
