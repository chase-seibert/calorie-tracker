# How to Work with StageChase

Use StageChase MCP tools to track requested work in the StageChase project for
this repository. Identify the project from `list_projects` and use its returned
stable ID; do not assume or invent a project ID. StageChase must be running on
this Mac with its **Settings → Connection → Codex Desktop MCP listener** enabled,
and the `stagechase` MCP server must be available in this Codex session.

If the tools are missing or the connection fails, explain the issue and ask the
user to reconnect the server. Do not read StageChase database or configuration
files to imitate MCP results, launch a nested `codex exec`, or copy the local
endpoint's secret token into project files, prompts, shell history, or source
control. The Local Wi-Fi sync listener is separate from the Codex Desktop MCP
listener.

## Find and start a task

- Use `list_projects` and `list_tasks` to find the task by stable ID. Call
  `read_task` with the exact project and task IDs before planning or
  implementation, and verify the returned IDs.
- Call `begin_task` only when the user asks to start planning or implementation
  in this Codex session. Use a fresh UUID `operation_id` and retain the returned
  `run_id` and latest task revision.
- For requested implementation, first move the task to `implementation`, using
  the latest revision and a fresh operation ID, then call `begin_task`.
- Every write must use the latest `expected_revision` and a fresh UUID
  `operation_id`. If a revision conflict occurs, reread the task before
  deciding how to proceed. Report concise progress with `report_task_update`
  when useful.

## Finish planning

- Save a readable, nonempty Markdown plan at
  `to-do/<normalized-task-title>-<lowercase-task-UUID>.md`, unless the user
  specified another path.
- If this session called `begin_task`, finish that run as `succeeded` after
  saving the plan and before editing the task; use the revision returned by
  `finish_task` for the next write.
- Attach the saved plan with `attach_task_plan`, then explicitly move the task
  to `planned`, using the latest revision and a fresh operation ID for each
  write. Planning leaves the task incomplete.
- If saving or attaching the plan fails, do not claim it is attached or move
  the task to `planned`. Report `needsInput` when user input is required. If
  `attach_task_plan` is unavailable, explain that the MCP server needs this
  tool.

## Finish implementation

- Implement the requested work and follow its attached plan when available.
- On success, call `finish_task` with status `succeeded` and a concise summary,
  then move the task to `review` using the latest revision and a fresh
  operation ID. Leave it incomplete.
- If implementation fails or is cancelled, call `finish_task` with the matching
  status and leave the task incomplete. Report `needsInput` when user input is
  required.
- Never call `set_task_completed` with `completed: true` unless the user
  explicitly asks to complete the task. If a requested review handoff requires
  reopening an already-completed task, set it to incomplete before moving it to
  `review`.

## Other task operations

Do not move or complete tasks as part of unrelated work. Task stage and
completion are separate fields: planning and implementation transitions apply
only to those requested workflows, and only an explicit user request can mark
a task complete. Do not infer board changes from a task title, attached plan,
successful implementation, or background status.
