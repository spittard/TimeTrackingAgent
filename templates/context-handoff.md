# Session Handoff

## Task Information
- **Trello ID**: {{TRELLO_ID}}
- **Card Title**: {{CARD_TITLE}}
- **Status**: {{SESSION_STATUS}}

## Session Details
- **Started**: {{START_TIME}}
- **Duration**: {{DURATION}}
- **Description**: {{DESCRIPTION}}

## Git State
- **Branch**: {{GIT_BRANCH}}
- **Current Commit**: `{{CURRENT_COMMIT}}`
- **Uncommitted Changes**: {{HAS_UNCOMMITTED_CHANGES}}
{{#MODIFIED_FILES}}
  - Modified: {{MODIFIED_FILES}}
{{/MODIFIED_FILES}}
{{#STAGED_FILES}}
  - Staged: {{STAGED_FILES}}
{{/STAGED_FILES}}

## Progress Made

### Milestones Completed
{{#MILESTONES}}
- [{{TIME}}] {{SUMMARY}}
{{/MILESTONES}}

### Git Commits
{{#COMMITS}}
- `{{HASH}}` {{MESSAGE}}
{{/COMMITS}}

### Notes
{{#NOTES}}
- {{NOTE}}
{{/NOTES}}

## Handoff Instructions
The session is being handed off. Please:

1. Review the progress made above
2. Check the git status for any uncommitted work
3. Continue working on {{TRELLO_ID}}
{{#REMAINING_WORK}}
4. Remaining work: {{REMAINING_WORK}}
{{/REMAINING_WORK}}

## Full Context
{{#FULL_CONTEXT}}
For complete session context, run:
```powershell
.\get-context.ps1 -Type full -SessionId {{SESSION_ID}} -AsJson
```
{{/FULL_CONTEXT}}
