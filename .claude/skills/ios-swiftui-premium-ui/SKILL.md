---
name: ios-swiftui-premium-ui
description: Use this skill whenever building or refactoring premium native iPhone SwiftUI screens, design systems, onboarding, dashboards, forms, paywalls, booking flows, or app UI.
---

You are building a premium native iOS app in SwiftUI.

Core principles:
- Native iOS first. Do not create web-like UI.
- Follow Apple Human Interface Guidelines.
- Use SwiftUI-native components, SF Symbols, Dynamic Type, safe areas, accessibility, haptics, and system spacing.
- Prioritize clarity, hierarchy, spacing, typography, animation restraint, and performance.
- UI should feel like a $100k polished iPhone app, not a generic AI-generated mockup.

Design rules:
- Use white or near-white base backgrounds unless instructed otherwise.
- Use subtle depth: material, shadows, blur, cards, dividers, and rounded corners only where they improve hierarchy.
- Avoid emoji, loud gradients, random icons, messy colors, and overdesigned cards.
- Use one strong accent color, not a rainbow palette.
- Use consistent spacing scale: 4 / 8 / 12 / 16 / 24 / 32.
- Use clear typography hierarchy:
  - LargeTitle for primary screens
  - Title2/Title3 for sections
  - Body/Subheadline for content
  - Caption only for metadata

SwiftUI architecture:
- Split screens into small reusable views.
- Create a design system:
  - AppTheme
  - AppSpacing
  - AppRadius
  - AppTypography
  - AppButtonStyle
  - AppCard
  - AppTextField
  - EmptyStateView
  - LoadingStateView
- Use MVVM only when state complexity requires it.
- Prefer clean View structs over unnecessary abstraction.

Before writing code:
1. Define screen goal.
2. Define user flow.
3. Define visual hierarchy.
4. Define reusable components.
5. Then implement SwiftUI.

After writing code:
1. Check compile errors.
2. Check preview/simulator rendering.
3. Improve spacing and hierarchy.
4. Remove generic AI-looking UI.
