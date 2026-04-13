# App Shell Tabs And Team Scope

## 1. Summary
- Clear description: Tab navigation, role-based tab visibility, unread message badge updates, and team scope selection in app chrome.
- User problem solved: Users navigate quickly while keeping active team context clear.
- Product value: Foundation for all in-app workflows.
- Repository: `izifoot-ios`.
- Status: existing.

## 2. Product Objective
- Why it exists: Mobile users need persistent nav and context with minimal friction.
- Target users: all authenticated roles.
- Context of use: `MainShellView`, `AppChrome`, `TeamScopePicker`.
- Expected outcome: role-consistent tabs and accurate team-scoped data.

## 3. Scope
Included
- `MainShellView.swift`, `AppTab.swift`, `AppChrome.swift`.
- `TeamScopeStore.swift`, `TeamScopePicker.swift`.
- unread badge handling via notifications.

Excluded
- Feature-specific page logic.

## 4. Actors
- Admin
Permissions: planning/messages/drills/players tabs plus admin routes.
Actions: switch active team and navigate full set.
Restrictions: backend still enforces scope.
- Coach
Permissions: planning/messages/drills/players.
Actions: scoped navigation.
Restrictions: managed-team limits.
- Parent
Permissions: planning/messages (and account access through chrome destinations).
Actions: consume linked child context.
Restrictions: no drills/players tab.
- Player
Permissions: planning/messages (and account).
Actions: consume own context.
Restrictions: no drills/players tab.
- Guest
Permissions: none.
Actions: none.
Restrictions: no shell.
- Unauthenticated user
Permissions: none.
Actions: none.
Restrictions: no shell.
- System
Permissions: computes default tab and unread badge state.
Actions: keeps shell synchronized with auth and notifications.
Restrictions: depends on API and notification events.

## 5. Entry Points
- UI: tab bar and chrome sheet actions.
- API: teams list and active team update via `TeamScopeStore`.
- System triggers: auth changes and unread badge notifications.

## 6. User Flows
- Main flow: login -> shell loads -> default tab selected by role.
- Variants: change team in picker and continue browsing.
- Back navigation: native navigation stacks per tab.
- Interruptions: team load failure.
- Errors: team switch errors surfaced in UI.
- Edge cases: role with no editable sport tabs.

## 7. Functional Behavior
- UI behavior: tab set changes by role capability (`canEditSportData`).
- Actions: choose tab, open chrome destinations, switch team.
- States: shell initialized, unread badge updated, team scope ready.
- Conditions: authenticated session required.
- Validations: selected team must exist in fetched team options.
- Blocking rules: no scope selection when role disallows it.
- Automations: unread badge update observer.

## 8. Data Model
- `AccountRole` and `AppTab` mapping.
Source: `APIModels.swift` and `AppTab.swift`.
Purpose: role-based navigation rules.
Format: enums.
Constraints: role list from backend contract.
- Team scope state
Source: teams endpoint and selected id.
Purpose: scope header injection.
Format: optional selected team id + option list.
Constraints: team membership.

## 9. Business Rules
- Default tab derived from account role.
- Team selector availability depends on role and team context.
- Unread badge should reflect notifications and resets.

## 10. State Machine
- Shell states: `INIT` -> `TAB_READY` -> `TEAM_SCOPE_READY`.
- Badge states: `UNKNOWN` -> `COUNT` updates.
- Invalid transitions: selecting protected tab for unauthorized role.

## 11. UI Components
- Native `TabView` tabs.
- App chrome header and action sheets.
- Team scope picker sheet.

## 12. Routes / API / Handlers
- Native navigation destinations in shell.
- API: teams list/update active team, unread count endpoint.

## 13. Persistence
- In-memory shell states.
- Team selection persistence through backend user profile/team endpoint.

## 14. Dependencies
- Upstream: auth state.
- Downstream: all feature screens using scoped API requests.
- Cross-repo: aligns with web shell/team-scope behavior.

## 15. Error Handling
- Validation: invalid team selection prevented by option list.
- Network: team bootstrap failures degrade gracefully.
- Missing data: no teams fallback.
- Permissions: backend enforces final scope.
- Current vs expected: limited user-facing diagnostics when scope bootstrap fails.

## 16. Security
- Access control: role-based tab visibility plus backend checks.
- Data exposure: scoped headers reduce overfetch risk.
- Guest rules: no shell access.

## 17. UX Requirements
- Feedback: visible selected team and unread badge.
- Errors: clear team-switch failure messaging.
- Empty states: no teams available state.
- Responsive: native behavior across iPhone/iPad sizes.

## 18. Ambiguities & Gaps
- Observed
- Team scope and chrome concerns are spread across several views/stores.
- Inferred
- Ongoing shell evolution for parity with web sidebar behaviors.
- Missing
- Central navigation map document.
- Tech debt
- Notification-driven unread sync may be hard to reason about.

## 19. Recommendations
- Product: publish role-to-tab matrix as contract.
- UX: explicit disabled-state explanation for unavailable tabs.
- Tech: centralize shell state orchestration.
- Security: add telemetry for failed team switch attempts.

## 20. Acceptance Criteria
1. Role-based tabs are correct for each user role.
2. Team switching updates API scope context.
3. Unread badges update from notifications.
4. Unauthorized tabs are not exposed.

## 21. Test Scenarios
- Happy path: coach switches team and navigates planning/messages.
- Permissions: parent does not see drills/players tabs.
- Errors: team list fetch failure.
- Edge cases: unread count notification arrives before shell ready.

## 22. Technical References
- `izifoot/Features/Shell/MainShellView.swift`
- `izifoot/Features/Shell/TeamScopeStore.swift`
- `izifoot/Features/Shell/TeamScopePicker.swift`
- `izifoot/Features/Shell/AppChrome.swift`
