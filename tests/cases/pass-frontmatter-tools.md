---
name: up (e.g.)
description: Makes what you ask for.
argument-hint: "<what you want, in your own words>"
allowed-tools: Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tree.py *)
tools: Read, Grep (e.g.)
model: sonnet
paths:
  - "src/**; e.g."
---

The body follows the style.
