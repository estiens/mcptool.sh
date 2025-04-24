#!/usr/bin/env bash

# MCP Tool - 'add' command target implementations
# This file contains functions specific to adding servers to different targets
# like Claude, Cursor, or generic JSON files.

# Ensure core functions are available if needed (adjust sourcing as necessary)
# source "$(dirname "${BASH_SOURCE[0]}")/mcplib_core.sh"
# Function to add server definition to Claude MCP
add_to_claude() {
  local server="$1"
  local servers_file="$2"
  local scope="$3" # Pass scope to the function

  echo "Adding $server definition to Claude MCP (Scope: $scope)..."

  # Check if Claude CLI is available
  if ! command -v claude &> /dev/null; then
    echo "Error: 'claude' command not found. Please ensure Claude CLI is installed and in your PATH." >&2
    return 1
  fi

  # Validate and get server definition
  # Need get_validated_server_definition from mcplib_core.sh
  local server_json
  server_json=$(get_validated_server_definition "$server" "$servers_file")
  if [ $? -ne 0 ]; then
    return 1 # Error message already printed by helper
  fi

  # Extract details from JSON (command already validated by helper)
  local server_cmd
  local server_args_array=()
  local env_opts=()
  server_cmd=$(echo "$server_json" | jq -r '.command')

  # Read args into a bash array
  server_args_array=()
  while IFS= read -r line; do
    server_args_array+=("$line")
  done < <(echo "$server_json" | jq -r '.args[]?' 2>/dev/null || echo "")

  # Check required environment variables (non-interactive)
  # Need ensure_env_vars_set from mcplib_core.sh
  local missing_env_vars
  # Assuming ensure_env_vars_set handles interaction if needed
  ensure_env_vars_set "$server" "$servers_file"
  local exit_code=$?

  if [ $exit_code -eq 2 ]; then # Error finding server
      echo "Error: Could not find server '$server' to check env vars." >&2 # More specific error
      return 1
  elif [ $exit_code -eq 1 ]; then # Missing env vars (user chose not to set them or failed)
      echo "Skipping addition of $server to Claude due to missing environment variables." >&2
      return 1
  fi
  # Exit code 0 means vars are set or were set successfully

  # Process environment variables for Claude's -e flag
  while read -r key_value; do
    # Skip empty lines
    [ -z "$key_value" ] && continue

    # Split into key and value
    local key="${key_value%%=*}"
    local value="${key_value#*=}"

    if [[ -n "$key" && -n "$value" ]]; then
      # Safely evaluate any ${VAR} references in the value
      evaluated_value=$(eval printf '%s' "$value" 2>/dev/null || echo "$value")

      # Store properly escaped option
      env_opts+=("-e" "$key=$evaluated_value")
    fi
  done < <(echo "$server_json" | jq -r '.env | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null || echo "")

  # Map mcptool scope to claude scope
  local claude_scope
  if [ "$scope" = "user" ]; then # Use 'user' scope from add_server
    claude_scope="user"
  else # Default to project scope
    claude_scope="project"
  fi

  # Build the claude command with arrays to avoid eval
  local claude_cmd=("claude" "mcp" "add" "--scope" "$claude_scope" "$server" "$server_cmd")

  # Add arguments if we have any (non-empty)
  for arg in "${server_args_array[@]}"; do
    [ -z "$arg" ] && continue
    claude_cmd+=("$arg")
  done

  # Add environment variables if we have any
  if [ ${#env_opts[@]} -gt 0 ]; then
    claude_cmd+=("${env_opts[@]}")
  fi

  # Show the command that will be executed
  echo "Executing: ${claude_cmd[*]}"

  # Execute the claude command directly without eval
  if ! "${claude_cmd[@]}"; then
    echo "Error: Failed to execute claude command. Check your Claude CLI installation." >&2
    return 1
  fi

  echo "Successfully added $server to Claude MCP (scope: $claude_scope)"
  return 0
}

# Function to add server definition to Cursor MCP config
add_to_cursor() {
  local server="$1"
  local servers_file="$2"
  local scope="$3"
  local overwrite=${4:-false} # Get overwrite flag (default false)
  local target_file
  local target_dir

  # Determine target file location based on scope
  if [ "$scope" = "user" ]; then # Use 'user' scope from add_server
    target_dir="$HOME/.cursor"
    target_file="$target_dir/mcp.json"
  else # Default to project
    target_dir="./.cursor"
    target_file="$target_dir/mcp.json"
  fi

  echo "Adding $server definition to Cursor MCP config ($target_file)..."

  # Handle overwrite flag
  if [ "$overwrite" = true ]; then
      if [ -f "$target_file" ]; then
          echo "Overwriting existing file: $target_file"
          rm -f "$target_file"
          if [ $? -ne 0 ]; then
              echo "Error: Failed to remove existing file for overwrite." >&2
              return 1
          fi
      fi
  fi

  # Extract server JSON definition
  # Need get_server_definition from mcplib_core.sh
  local server_json
  server_json=$(get_server_definition "$server" "$servers_file")

  if [ -z "$server_json" ] || [ "$server_json" = "null" ]; then
    echo "Error: Server '$server' not found in config '$servers_file'." >&2
    return 1
  fi

  # Check required environment variables (interactive)
  # Need ensure_env_vars_set from mcplib_core.sh
  ensure_env_vars_set "$server" "$servers_file"
  local exit_code=$?

  if [ $exit_code -eq 2 ]; then # Error finding server
      echo "Error: Could not find server '$server' to check env vars." >&2 # More specific error
      return 1
  elif [ $exit_code -eq 1 ]; then # Missing env vars (user chose not to set them or failed)
      echo "Skipping addition of $server to Cursor due to missing environment variables." >&2
      return 1
  fi
  # Exit code 0 means vars are set or were set successfully

  # Ensure target directory exists with proper permissions
  if ! mkdir -p "$target_dir"; then
    echo "Error: Could not create target directory $target_dir" >&2
    return 1
  fi

  # Check target file status and prepare it
  local temp_json_file # Declare temp file used in multiple blocks
  temp_json_file=$(mktemp)
  chmod 600 "$temp_json_file"
  # Register automatic cleanup earlier
  trap 'rm -f "$temp_json_file" 2>/dev/null || true' EXIT INT TERM

  if [ ! -f "$target_file" ]; then
    # Create file with initial structure if it doesn't exist
    echo '{ "mcpServers": {} }' > "$target_file"
    chmod 644 "$target_file"  # Reasonable default permissions
    echo "Created new Cursor MCP configuration file at $target_file"
  elif ! jq empty "$target_file" 2>/dev/null; then
    # If file exists but isn't valid JSON, back it up and reset
    local backup_file="${target_file}.bak.$(date +%Y%m%d%H%M%S)"
    echo "Error: Target file $target_file is not valid JSON. Cannot merge." >&2
    echo "Backing up invalid file to $backup_file"

    if ! cp "$target_file" "$backup_file"; then
      echo "Error: Failed to create backup of invalid configuration file" >&2
      # rm -f "$temp_json_file" # Clean up temp file on error
      return 1
    fi

    # Don't completely overwrite, attempt to salvage content
    if grep -q "mcpServers" "$backup_file"; then
      echo "Attempting to salvage existing content..."
      # Try to extract just the mcpServers object
      salvaged_content=$(jq -c '.mcpServers // {}' "$backup_file" 2>/dev/null)
      if [ -n "$salvaged_content" ] && [ "$salvaged_content" != "null" ]; then
          echo "{\"mcpServers\": $salvaged_content}" > "$target_file"
      else
          echo '{ "mcpServers": {} }' > "$target_file"
      fi
    else
      echo '{ "mcpServers": {} }' > "$target_file"
    fi

    # Verify we created valid JSON
    if ! jq empty "$target_file" 2>/dev/null; then
      echo "Failed to salvage content, starting with empty configuration."
      echo '{ "mcpServers": {} }' > "$target_file"
    fi

    echo "Reset invalid Cursor MCP configuration file at $target_file"
  fi

  # Check if we can write to the target file
  if [ ! -w "$target_file" ]; then
    echo "Error: No permission to write to $target_file" >&2
    # rm -f "$temp_json_file" # Clean up temp file on error
    return 1
  fi

  # Check if mcpServers key exists in the target file, add if not
  if ! jq -e '.mcpServers' "$target_file" >/dev/null 2>&1; then
      # If "mcpServers" doesn't exist but "servers" does, try to migrate
      if jq -e '.servers' "$target_file" >/dev/null 2>&1; then
        echo "Warning: Target file uses 'servers' instead of 'mcpServers'. Migrating to 'mcpServers'..."
        jq '. + {"mcpServers": (.servers // {})} | del(.servers)' "$target_file" > "$temp_json_file" && mv "$temp_json_file" "$target_file"
      else
        # If neither exists, add mcpServers
        jq '. + {"mcpServers": {}}' "$target_file" > "$temp_json_file" && mv "$temp_json_file" "$target_file"
      fi
      # Re-check after attempting fix
      if ! jq -e '.mcpServers' "$target_file" >/dev/null 2>&1; then
          echo "Error: Failed to ensure 'mcpServers' key exists in $target_file" >&2
          return 1
      fi
  fi

  # Re-validate and get server definition (env vars might have changed values)
  # Need get_validated_server_definition from mcplib_core.sh
  server_json=$(get_validated_server_definition "$server" "$servers_file")
  if [ $? -ne 0 ]; then
    # rm -f "$temp_json_file" # Clean up temp file on error
    return 1 # Error message already printed by helper
  fi

  # Process environment variables in server definition to resolve ${VAR} references
  # Need process_env_vars_json from mcplib_core.sh (or similar logic)
  local processed_server_json
  processed_server_json=$(echo "$server_json" | jq '.') # Start with original JSON

  if echo "$server_json" | jq -e 'has("env")' >/dev/null 2>&1; then
    while read -r key_value; do
      [ -z "$key_value" ] && continue
      local key="${key_value%%=*}"
      local value="${key_value#*=}"
      if [[ -n "$key" && -n "$value" ]]; then
        local evaluated_value
        # Use direct variable expansion if possible, fallback to eval for complex cases
        # This is safer than blanket eval
        if [[ "$value" =~ ^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$ ]]; then
             var_name=$(echo "$value" | sed 's/^\${//; s/}$//')
             evaluated_value="${!var_name}"
        else
             # Fallback for more complex substitutions, use with caution
             evaluated_value=$(eval printf '%s' "$value" 2>/dev/null || echo "$value")
        fi
        # Update the JSON with the evaluated value
        processed_server_json=$(echo "$processed_server_json" | jq --arg key "$key" --arg value "$evaluated_value" '.env[$key] = $value')
      fi
    done < <(echo "$server_json" | jq -r '.env | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null || echo "")
  fi

  # Merge the processed server definition to mcpServers object
  # Use sponge or a temp file for reliable in-place update
  if ! jq --arg server "$server" --argjson definition "$processed_server_json" \
     '.mcpServers[$server] = $definition' "$target_file" > "$temp_json_file"; then
    echo "Error: Failed to merge server definition into temp file. Check JSON format." >&2
    # rm -f "$temp_json_file" # Clean up temp file on error
    return 1
  fi

  # Verify the merged result is valid JSON
  if ! jq empty "$temp_json_file" 2>/dev/null; then
    echo "Error: Generated configuration in temp file is not valid JSON. This is likely a bug." >&2
    # rm -f "$temp_json_file" # Clean up temp file on error
    return 1
  fi

  # Move the new file into place
  if mv "$temp_json_file" "$target_file"; then
    echo "Successfully added/updated $server in $target_file under mcpServers"

    # Show brief summary of the updated server
    echo "Server details:"
    jq --arg server "$server" '.mcpServers[$server] | {command, description: (.description // "No description")}' "$target_file" |
      sed 's/^/  /' # Indent the output

    # rm -f "$temp_json_file" # Cleanup already handled by trap
    return 0
  else
    echo "Error: Failed to write updated configuration to $target_file" >&2
    # rm -f "$temp_json_file" # Ensure cleanup even if mv fails
    return 1
  fi
}

# Placeholder for add_to_json if needed, or keep it within add_server in mcplib_commands.sh
# add_to_json() { ... }