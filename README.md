# Condor Discovery PoC — Claude Code task pack

Unzip this at the root of the PoC repository.

- `CLAUDE.md` — standing rules every agent loads first. Claude Code reads it automatically.
- `PLAN.md` — all 58 tasks with dependencies, gates and parallel waves, plus the human gate list.
- `tasks/<ID>.md` — one self-contained task definition per agent session.
- `tasks/STATUS.md` — the shared status board agents update.
- `tasks/_TEMPLATE.md` — use it for any task added later.

Operator prerequisites before the first agent runs `P1-01`:

1. Set `CONDOR_ACCOUNT_ID`, and `GITHUB_ORG` in the agent environment.
2. Admin access to the account for the one-time bootstrap apply, and an operator principal ARN for the role trust.
3. A GitHub organization where you are an owner.
4. A monthly budget figure for `monthly_budget_usd`.

Start an agent with: `Execute task P1-01. Follow CLAUDE.md.`
