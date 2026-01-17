# Resume Work Context

## Last Session
- **Task**: {{TRELLO_ID}} - {{CARD_TITLE}}
- **Ended**: {{END_TIME}}
- **Duration**: {{DURATION}}

## What Was Accomplished
{{#MILESTONES}}
- {{MILESTONE}}
{{/MILESTONES}}

## Git Commits Made
{{#COMMITS}}
- `{{HASH}}` {{MESSAGE}}
{{/COMMITS}}

## Current Git State
- **Branch**: {{GIT_BRANCH}}
{{#HAS_CHANGES}}
- **Uncommitted Changes**: Yes
  - Modified: {{MODIFIED_COUNT}} files
  - Staged: {{STAGED_COUNT}} files
{{/HAS_CHANGES}}
{{^HAS_CHANGES}}
- **Uncommitted Changes**: No
{{/HAS_CHANGES}}

## Suggested Next Steps
1. Review the progress made in the last session
2. Start a new session: `start-clock.ps1 -TrelloId {{TRELLO_ID}}`
3. Continue from where you left off

## Context Notes
{{NOTES}}
