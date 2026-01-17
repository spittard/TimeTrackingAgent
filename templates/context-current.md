# Current Session Context

## Task
- **Trello ID**: {{TRELLO_ID}}
- **Card Title**: {{CARD_TITLE}}
- **Started**: {{START_TIME}}
- **Elapsed**: {{ELAPSED}}

## Git State
- **Branch**: {{GIT_BRANCH}}
{{#MODIFIED}}
- **Modified**: {{MODIFIED_FILES}}
{{/MODIFIED}}
{{#STAGED}}
- **Staged**: {{STAGED_FILES}}
{{/STAGED}}

## Progress So Far
{{#PROGRESS_POINTS}}
{{INDEX}}. [{{TIME}}] {{SUMMARY}}
{{/PROGRESS_POINTS}}

## Recent Activity
{{#ACTIVITY}}
- {{ACTIVITY_ITEM}}
{{/ACTIVITY}}

## Instructions
Continue working on {{TRELLO_ID}}. {{CUSTOM_INSTRUCTIONS}}
