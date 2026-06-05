#!/bin/bash

# Helper to start an MLR MCP server locally for testing/debugging over stdio.
# Claude Code launches these automatically from .mcp.json; this is for manual CLI debugging.

WORKSPACE_PATH="/Users/minholee/Projects/gen-ai-interview"

print_usage() {
  echo "Usage: $0 [fetch|filesystem]"
  echo "  fetch       - Starts the Fetch MCP server (HTTP→Markdown; e.g. PubMed/openFDA pages)"
  echo "  filesystem  - Starts the Filesystem MCP server (scoped to the project)"
}

if [ -z "$1" ]; then
  print_usage
  exit 1
fi

case "$1" in
  fetch)
    echo "Starting Fetch MCP Server..."
    npx -y fetch-mcp
    ;;
  filesystem)
    echo "Starting Filesystem MCP Server scoped to $WORKSPACE_PATH..."
    npx -y @modelcontextprotocol/server-filesystem "$WORKSPACE_PATH"
    ;;
  *)
    echo "Error: Unknown server '$1'"
    print_usage
    exit 1
    ;;
esac
