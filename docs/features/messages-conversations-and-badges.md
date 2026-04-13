# Messages Conversations And Badges

## 1. Summary
- Clear description: Conversation list/detail messaging plus unread badge synchronization.
- User problem solved: Mobile communication with team and coach/player threads.
- Product value: Core engagement and coordination channel.
- Repository: `izifoot-ios`.
- Status: existing.

## 2. Product Objective
- Why it exists: Real-time operational communication on mobile.
- Target users: authenticated roles.
- Context of use: messages tab.
- Expected outcome: users can read and send messages in allowed conversations.

## 3. Scope
Included
- `MessagesView.swift` conversation and thread views.
- unread count updates consumed by `MainShellView` badge.
- message send flow.

Excluded
- Team feed-only web implementation differences.

## 4. Actors
- Admin
Permissions: scoped conversation access.
Actions: read/send messages.
Restrictions: scope enforced.
- Coach
Permissions: scoped conversation access.
Actions: read/send messages.
Restrictions: scope.
- Parent
Permissions: linked-player conversation and team context.
Actions: read/send where allowed.
Restrictions: scope.
- Player
Permissions: own conversation context.
Actions: read/send where allowed.
Restrictions: scope.
- Guest
Permissions: none.
Actions: none.
Restrictions: blocked.
- Unauthenticated user
Permissions: none.
Actions: none.
Restrictions: blocked.
- System
Permissions: fetch unread count and publish notification updates.
Actions: keep tab/app badge aligned.
Restrictions: depends on message read state and API.

## 5. Entry Points
- UI: messages tab and nested conversation views.
- API: conversations list/messages/send, unread count.

## 6. User Flows
- Main flow: open messages -> select conversation -> read/send message.
- Variants: unread count updates after interactions.
- Back navigation: thread back to conversation list.
- Interruptions: send failure.
- Errors: alert error states.
- Edge cases: empty conversation list.

## 7. Functional Behavior
- UI behavior: list of conversations with metadata and thread history.
- Actions: fetch conversations/messages and post new message.
- States: loading, loaded, sending, error.
- Conditions: authenticated and scoped context.
- Validations: non-empty message content before send.
- Blocking rules: disable send while posting.
- Automations: badge updates via notification center.

## 8. Data Model
- `MessageConversation`, `ConversationMessage`, unread count response.
Source: messaging APIs.
Purpose: thread rendering and badge display.
Format: codable structs.
Constraints: role/team scoped.

## 9. Business Rules
- Conversation list may be filtered by active team context.
- Read/sent actions should influence unread badge state.
- Conversation id contract from backend must stay stable.

## 10. State Machine
- Conversation states: unloaded/loaded/error.
- Thread states: loading/sending/ready/error.
- Badge states: unknown/count.
- Invalid transitions: send message without selected conversation.

## 11. UI Components
- Conversation list view.
- Thread detail view.
- Message composer.
- Tab badge indicator.

## 12. Routes / API / Handlers
- Native views in messages module.
- API: `/messages/conversations`, `/messages/conversations/:id/messages`, `/team-messages/unread-count`.

## 13. Persistence
- Client: in-memory conversation/thread state.
- Backend: direct/team message and read markers.

## 14. Dependencies
- Upstream: auth and team scope.
- Downstream: shell badge and app icon badge reset logic.
- Cross-repo: web currently focuses more on team feed UX.

## 15. Error Handling
- Validation: empty message prevented.
- Network: thread-level alerting and retry paths.
- Missing data: absent conversation handled gracefully.
- Permissions: forbidden scope operations blocked by backend.
- Current vs expected: offline draft support not observed.

## 16. Security
- Access control: authenticated and scoped API access.
- Data exposure: only allowed conversation threads returned.
- Guest rules: no access.

## 17. UX Requirements
- Feedback: send progress and failure alerts.
- Empty states: no conversations.
- Loading: clear progress for thread loads.
- Responsive: native messaging ergonomics.

## 18. Ambiguities & Gaps
- Observed
- Messaging model differs between web and iOS emphasis.
- Inferred
- Cross-platform convergence is still in progress.
- Missing
- Shared UX spec for conversation/thread parity.
- Tech debt
- Badge synchronization relies on distributed notification events.

## 19. Recommendations
- Product: define unified messaging experience across clients.
- UX: add optimistic send and message delivery indicators.
- Tech: centralize unread state handling.
- Security: monitor abuse/spam and apply server-side controls.

## 20. Acceptance Criteria
1. User can load conversations and thread history.
2. User can send messages in allowed threads.
3. Unread badge updates after reads/sends.
4. Errors do not break navigation flow.

## 21. Test Scenarios
- Happy path: send message in a coach conversation.
- Permissions: access denied for out-of-scope team.
- Errors: message send failure.
- Edge cases: unread badge remains stale after offline period.

## 22. Technical References
- `izifoot/Features/Messages/MessagesView.swift`
- `izifoot/Features/Shell/MainShellView.swift`
- `izifoot/Core/Networking/IzifootAPI.swift`
