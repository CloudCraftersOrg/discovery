# PX-NN · <Title>

| Field | Value |
|---|---|
| Phase | <phase name> |
| Stream | I / P / I+P |
| Depends | <task IDs or none> |
| Gate | `none` / `review` / `approve-apply` / `human-action` / `wait` |
| Paths | <the only paths this task may change> |

Before starting: read `CLAUDE.md`, confirm every dependency is `done` in `tasks/STATUS.md`, run the account guard for any AWS write.

**Goal.** One or two sentences: the outcome, not the activity.

**Read first.** Files and specs the agent must load.

**Build**
- Concrete names, sizes, versions-or-how-to-resolve-them, tags, and exact behaviour.
- Mark planted estate defects with their answer-key ID.

**Acceptance**
- [ ] Commands or queries with the expected result. Every item must be checkable by the agent.

**Out of scope.** What the agent must not do even if it looks related.

**Stop and ask if** the specific conditions under which guessing would be harmful.

**Cost limit.** USD per hour, if the task creates billable resources.
