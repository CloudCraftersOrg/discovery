# harness

Shared platform tooling that isn't itself an application: the Jenkins controller, the self-hosted GitHub runner. Never treated as an app in grouping logic.

`ledger.jsonl` (append-only, one JSON object per line) records timestamps for planted human-identity changes and, later, generated deploy/traffic history - see P1-13 and P1-14. `estate/verify/generate_refs.py` and `check_planted.py` read it; nothing regenerates it, so never overwrite it wholesale.
