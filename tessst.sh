#!/bin/bash

# Fix Grammar

TITLE="Fix Grammar"

PROMPT="Rewrite the following <transcript> text for clarity and naturalness.
Preserve its meaning, language, register, tone, and approximate length.
If no changes are needed, return it unchanged.
Return only the rewritten text.

Never use the em dash ('—'). Use a hyphen ('-') instead.
Prefer straight apostrophes (') over typographic apostrophes (’) in
contractions and possessives (e.g. I'm, we're, user's).
"

INPUT="Done. Committed 32cd5629b9 (fix(antares): enable tab navigation for nested card controls) and pushed it to PR #346 on feat/card-component. The working tree is clean.

Posted both replies as egaitan-godaddy: [Save button thread](https://github.com/godaddy/antares/pull/346#discussion_r4225352724) and [Switch and DNS link thread](https://github.com/godaddy/antares/pull/346#discussion_r4225353100). Copilot had resolved both threads after the push; I replied as requested.
"

make dev \
  FLOATER_PROMPT="$PROMPT" \
  FLOATER_TITLE="$TITLE" \
  FLOATER_INPUT="$INPUT"
