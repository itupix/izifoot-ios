# Stats And Public Matchday

## 1. Summary
- Clear description: Stats overview for internal users and token-based public matchday screen.
- User problem solved: Quick operational metrics and external read-only sharing on mobile.
- Product value: performance visibility plus stakeholder communication.
- Repository: `izifoot-ios`.
- Status: existing (stats depth basic).

## 2. Product Objective
- Why it exists: Mobile users need lightweight analytics and public share consumption.
- Target users: direction/coach for stats, any token holder for public page.
- Context of use: `StatsHomeView` and `PublicMatchdayView`.
- Expected outcome: reliable KPI snapshots and public matchday render.

## 3. Scope
Included
- stats data aggregation from multiple endpoints.
- public matchday fetch by token and display.

Excluded
- advanced analytics segmentation/filtering.

## 4. Actors
- Admin
Permissions: internal stats view access.
Actions: monitor KPIs.
Restrictions: scoped datasets.
- Coach
Permissions: internal stats view access.
Actions: monitor KPIs.
Restrictions: scoped datasets.
- Parent
Permissions: no internal stats, can open public token screen.
Actions: consume shared matchday.
Restrictions: no protected analytics.
- Player
Permissions: same as parent for public screen.
Actions: consume shared matchday.
Restrictions: no protected analytics.
- Guest
Permissions: public token view only.
Actions: view shared matchday.
Restrictions: token required.
- Unauthenticated user
Permissions: same as guest for public token route.
Actions: public read only.
Restrictions: no protected tabs.
- System
Permissions: aggregates data client-side and renders public payload.
Actions: compute metrics and handle token errors.
Restrictions: reliant on endpoint consistency.

## 5. Entry Points
- UI: stats tab and public matchday entry view.
- API: stats source endpoints and `/public/matchday/:token`.

## 6. User Flows
- Main flow (stats): open tab -> fetch datasets -> show aggregates.
- Main flow (public): open token input/link -> load public matchday.
- Back navigation: standard tab/back navigation.
- Interruptions: one or more dataset failures.
- Errors: alert and fallback states.
- Edge cases: empty datasets or invalid token.

## 7. Functional Behavior
- UI behavior: summary cards and read-only public details.
- Actions: read-only fetches.
- States: loading, ready, empty, error.
- Conditions: stats requires authenticated privileged role.
- Validations: token validity for public fetch.
- Blocking rules: no writes.
- Automations: none.

## 8. Data Model
- Stats sources: players/trainings/matchdays/drills (as observed).
Source: multiple endpoints.
Purpose: high-level KPI rendering.
Format: arrays aggregated client-side.
Constraints: data freshness and consistency.
- Public matchday model
Source: token endpoint.
Purpose: read-only shared display.
Format: codable matchday structure.
Constraints: sanitized fields.

## 9. Business Rules
- Stats are derived client-side from current scoped datasets.
- Public view is strictly read-only and token-gated.

## 10. State Machine
- Stats: loading -> ready/error.
- Public: token input/loading/ready/error.
- Invalid transitions: stats render without required auth context.

## 11. UI Components
- Stats cards/lists.
- Public matchday detail view.
- Error alerts.

## 12. Routes / API / Handlers
- Native views: `StatsHomeView`, `PublicMatchdayView`.
- API: aggregate source endpoints and public token endpoint.

## 13. Persistence
- Client: temporary in-memory aggregate results.
- Backend: canonical domain tables.

## 14. Dependencies
- Upstream: planning, players, drills, matches data quality.
- Downstream: operational decisions and external communication.
- Cross-repo: web has equivalent stats and public route.

## 15. Error Handling
- Validation: token required for public fetch.
- Network: alert and fallback rendering.
- Missing data: empty stats/public states.
- Permissions: stats hidden/blocked for unsupported roles.
- Current vs expected: server-side aggregate endpoint absent.

## 16. Security
- Access control: stats protected; public endpoint tokenized.
- Data exposure: public payload must remain minimal.
- Guest rules: only public view allowed.

## 17. UX Requirements
- Feedback: clear invalid token and data-load messages.
- Empty states: no metrics or no public data.
- Loading: visible progress indicators.
- Responsive: native adaptive layout.

## 18. Ambiguities & Gaps
- Observed
- Stats are computed client-side only.
- Inferred
- Scalability may degrade with larger datasets.
- Missing
- Server-side KPI API for consistent analytics.
- Tech debt
- Potential drift between web and iOS stat computations.

## 19. Recommendations
- Product: prioritize KPI definitions and threshold alerts.
- UX: add filters by date/team.
- Tech: centralize aggregate computations or move backend-side.
- Security: audit public payload fields regularly.

## 20. Acceptance Criteria
1. Direction/coach can view stats without app errors.
2. Public token loads read-only matchday.
3. Invalid token shows deterministic error.
4. Empty datasets are handled gracefully.

## 21. Test Scenarios
- Happy path: stats load with populated datasets.
- Permissions: parent cannot access internal stats view.
- Errors: one stats endpoint fails.
- Edge cases: expired or malformed public token.

## 22. Technical References
- `izifoot/Features/Stats/StatsHomeView.swift`
- `izifoot/Features/Public/PublicMatchdayView.swift`
- `izifoot/Core/Networking/IzifootAPI.swift`
