---
name: handoff
description: >-
  Manages the context window. Run "/handoff save" to document the current state,
  or "/handoff load" to resume after clearing context.
---
## Skill Instructions

You are managing the project's `WORKING_STATE.md` file to help the user preserve context across resets. Determine the user's intent based on their prompt and follow the corresponding workflow:

### If the user wants to SAVE (e.g., "save", "handoff", "generate"):
1. Analyze the conversation history, current project state, and recent file changes.
2. Create or overwrite a file named `WORKING_STATE.md` in the root of the project.
3. Write a comprehensive summary including:
   - **Project Goal:** What we are currently trying to achieve.
   - **Current Status:** What was just completed and verified.
   - **Key Decisions:** Important architectural or logic choices made in this session.
   - **Active Files:** Paths to the files we were currently modifying.
   - **Immediate Next Steps:** Exactly what the next task should be.
4. Confirm completion and advise the user they can now safely run `/clear`.

### If the user wants to LOAD (e.g., "load", "resume", "accept"):
1. You MUST explicitly read the file contents. Use your file reading tool. Do not use `find` or assume the file doesn't exist without attempting to read first.
2. Silently process the text contents of the file to understand the current project state, active files, and next steps.
3. Reply ONLY with a brief confirmation that you understand the project state, list the immediate next step.

