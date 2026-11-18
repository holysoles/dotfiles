---
name: aws
description: >-
  Use for AWS questions or work, including service behavior, implementation,
  infrastructure, debugging, and account investigations. Verify current guidance
  with AWS documentation and load the relevant AWS skill before proceeding.
---

# AWS

- Follow the project's instructions if they conflict with this guidance.
- Use Pi's `codemode` to access AWS MCP tools. Discover them with
  `searchTools("AWS documentation search agent_skills")`. If that returns no
  matches, inspect `ALL_TOOLS` for AWS/documentation-related names or
  descriptions; don't assume a fixed namespace or tool-name prefix. Use
  `describeTool(name)` to confirm the exact signature before calling the
  discovered tool. If no relevant tools are exposed, say so and don't claim
  current AWS documentation was verified.
- For AWS tasks, use the AWS documentation search tool with topic `agent_skills`,
  then load the matching guidance with the AWS skill retrieval tool. Use the
  documentation read tool when you need the full page. Prefer current AWS MCP
  documentation over memory.
- Verify uncertain details against current AWS documentation. Separate confirmed
  evidence from hypotheses, and say what remains unverified.
- For investigations, inspect runtime configuration and primary records. Read
  complete records before interpreting them. Paginate and cover relevant regions
  and scopes before reporting totals or absence; state any limits in coverage.
- Prefer CDK or CloudFormation for infrastructure changes and follow the AWS
  Well-Architected Framework.
- For secrets, load the `aws-secrets-manager` skill first. Never call Secrets
  Manager `get-secret-value` or `batch-get-secret-value`, or access its agent
  daemon directly. Use `{{resolve:secretsmanager:secret-id:SecretString:json-key}}`
  with `asm-exec` so secrets resolve at runtime without entering context.
