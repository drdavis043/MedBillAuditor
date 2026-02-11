//
//  Theme.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 2/10/26.
//
import SwiftUI
/// Centralized theme for consistent styling across the app.
enum AppTheme {
    // MARK: - Colors
    enum Colors {
        static let primary = Color("ThemePrimary", bundle: nil)
        static let accent = Color.blue
        // Status colors
        static let success = Color(red: 0.20, green: 0.72, blue: 0.40)
        static let warning = Color(red: 0.95, green: 0.65, blue: 0.15)
        static let danger = Color(red: 0.90, green: 0.25, blue: 0.20)
        static let info = Color(red: 0.20, green: 0.55, blue: 0.85)
        // Background colors
        static let background = Color(.systemBackground)
        static let secondaryBackground = Color(.secondarySystemBackground)
        static let groupedBackground = Color(.systemGroupedBackground)
        // Severity colors
        static func severity(_ level: FlagSeverity) -> Color {
            switch level {
            case .critical: return danger
            case .warning: return warning
            case .info: return info
            }
        }
        // Bill status colors
        static func status(_ status: BillStatus) -> Color {
            switch status {
            case .captured, .parsing: return .gray
            case .parsed: return info
            case .auditing: return warning
            case .audited: return Color.purple
            case .disputed: return danger
            case .resolved: return success
            }
        }
    }
    // MARK: - Typography
    enum Typography {
        static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let title = Font.system(.title2, design: .rounded, weight: .bold)
        static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
        static let body = Font.system(.body, design: .default)
        static let caption = Font.system(.caption, design: .default)
        static let code = Font.system(.caption, design: .monospaced, weight: .medium)
    }
    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }
    // MARK: - Corner Radius
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let pill: CGFloat = 100
    }
}
// MARK: - Reusable View Modifiers
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}
struct BadgeStyle: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .font(AppTheme.Typography.code)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
    }
}
struct SeverityBadge: ViewModifier {
    let severity: FlagSeverity
    func body(content: Content) -> some View {
        content
            .modifier(BadgeStyle(color: AppTheme.Colors.severity(severity)))
    }
}
extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
    func badge(color: Color) -> some View {
        modifier(BadgeStyle(color: color))
    }
    func severityBadge(_ severity: FlagSeverity) -> some View {
        modifier(SeverityBadge(severity: severity))
    }
}
