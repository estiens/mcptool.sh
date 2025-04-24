#!/usr/bin/env bash

# MCP Tool - Generators
# This file contains functions that generate output files or content,
# such as documentation, autoloader scripts, and custom group files.

# Ensure core functions are available if needed (adjust sourcing as necessary)
# source "$(dirname "${BASH_SOURCE[0]}")/mcplib_core.sh"
# Generate autoloader for shell integration
generate_autoloader() {
  local autoloader_file="$1"
  local script_path="$2"

  # Create parent directory if it doesn't exist
  mkdir -p "$(dirname "$autoloader_file")"

  # Check if file exists already and back it up if it does
  if [ -f "$autoloader_file" ]; then
    cp "$autoloader_file" "${autoloader_file}.bak"
    echo "Backed up existing autoloader to ${autoloader_file}.bak"
  fi

  cat > "$autoloader_file" << EOF
# MCP Tool Autoloader
# Auto-generated on $(date)
# Add this to your shell configuration file to enable MCP Tool functionality

# Set default MCP configuration file location
export MCP_CONFIG_FILE="\${MCP_CONFIG_FILE:-\$HOME/.config/mcp_servers.json}"

# Create alias for MCP Tool
alias mcpt="$script_path"

# Function to list available MCP servers
mcpt_list() {
  "$script_path" list "\$@"
}

# Function to run an MCP server
mcpt_run() {
  if [ -z "\$1" ]; then
    echo "Usage: mcpt_run <server_name|group_name>"
    return 1
  fi
  "$script_path" run "\$1" "\$@"
}

# Function to get info about an MCP server or group
mcpt_info() {
  if [ -z "\$1" ]; then
    echo "Usage: mcpt_info <server_name|group_name> [-v|--verbose]"
    return 1
  fi
  "$script_path" info "\$1" "\$@"
}

# Function to get JSON definition for a server or group
mcpt_json() {
  if [ -z "\$1" ]; then
    echo "Usage: mcpt_json <server_name|group_name>"
    return 1
  fi
  "$script_path" json "\$1" "\$@"
}

# Function to add server to Claude MCP
mcpt_claude() {
  if [ -z "\$1" ]; then
    echo "Usage: mcpt_claude <server_name|group_name> [--project|--global]"
    return 1
  fi
  "$script_path" claude "\$1" "\$@"
}

# Function to add server to Cursor MCP
mcpt_cursor() {
  if [ -z "\$1" ]; then
    echo "Usage: mcpt_cursor <server_name|group_name> [--project|--global]"
    return 1
  fi
  "$script_path" cursor "\$1" "\$@"
}

# Function to output MCP server documentation
mcpt_docs() {
  "$script_path" docs "\$@"
}

# Function to launch interactive server selection
mcpt_interactive() {
  "$script_path" interactive "\$@"
}

# Function to run setup wizard for a server
mcpt_setup() {
  if [ -z "\$1" ]; then
    echo "Usage: mcpt_setup <server_name>"
    return 1
  fi
  "$script_path" setup "\$1" "\$@"
}

# Tab completion for MCP servers and groups
_mcpt_completion() {
  local servers=\$("$script_path" list 2>/dev/null | grep -A 100 "Available servers:" | grep -B 100 "Available groups:" | grep -v "Available servers:" | grep -v "Available groups:" | sed 's/^  //')
  local groups=\$("$script_path" list 2>/dev/null | grep -A 100 "Available groups:" | grep -v "Available groups:" | sed 's/^  //')
  local commands="list run info json claude cursor docs interactive setup autoloader version help"

  if [[ \$CURRENT -eq 2 ]]; then
    _alternative \\
      'commands:command:compadd -a commands' \\
      'servers:server:compadd -a servers' \\
      'groups:group:compadd -a groups'
  elif [[ \$CURRENT -eq 3 && (\${words[2]} == "run" || \${words[2]} == "info" || \${words[2]} == "setup" || \${words[2]} == "json" || \${words[2]} == "claude" || \${words[2]} == "cursor") ]]; then
    _alternative \\
      'servers:server:compadd -a servers' \\
      'groups:group:compadd -a groups'
  elif [[ \$CURRENT -eq 3 && \${words[2]} == "help" ]]; then
    _alternative \\
      'commands:command:compadd -a commands'
  elif [[ \$CURRENT -ge 3 && (\${words[2]} == "claude" || \${words[2]} == "cursor") ]]; then
    _alternative \\
      'options:option:compadd --project --global'
  elif [[ \$CURRENT -ge 3 && \${words[2]} == "info" ]]; then
    _alternative \\
      'options:option:compadd -v --verbose'
  fi
}

# Set up completions for both mcpt command and the alias
compdef _mcpt_completion "$script_path"
compdef _mcpt_completion mcpt
EOF

  echo "Autoloader file generated at: $autoloader_file"
  echo "To use it, add the following line to your shell configuration file (.zshrc):"
  echo "source $autoloader_file"
}

# Generate comprehensive documentation for all servers
generate_documentation() {
  local servers_file="$1"
  local groups_file="$2"

  local all_servers=$(get_servers "$servers_file")
  local all_groups=$(get_groups "$groups_file")

  echo "# MCP Servers Documentation"
  echo ""
  echo "This document provides comprehensive information about all available MCP servers."
  echo "Generated on $(date)"
  echo ""

  # Document all servers
  echo "## Available Servers"
  echo ""

  if [ -z "$all_servers" ]; then
    echo "No servers defined in the configuration file."
    echo ""
  else
    for SERVER in $all_servers; do
      SERVER_DEF=$(get_server_definition "$SERVER" "$servers_file")
      SERVER_DESC=$(echo "$SERVER_DEF" | jq -r '.description // "No description"')
      SERVER_CMD=$(echo "$SERVER_DEF" | jq -r '.command')
      SERVER_ARGS=$(echo "$SERVER_DEF" | jq -r '.args | join(" ")' 2>/dev/null || echo "")
      REQUIRED_ENVS=$(echo "$SERVER_DEF" | jq -r '.required_env[]?')

      echo "### $SERVER"
      echo ""
      echo "**Description:** $SERVER_DESC"
      echo ""
      echo "**Command:** \`$SERVER_CMD $SERVER_ARGS\`"
      echo ""

      if [ -n "$REQUIRED_ENVS" ]; then
        echo "**Required Environment Variables:**"
        echo ""
        for ENV_VAR in $REQUIRED_ENVS; do
          echo "- \`$ENV_VAR\`"
        done
        echo ""
      fi

      # Check which groups this server belongs to
      GROUPS=""
      for GROUP in $all_groups; do
        GROUP_SERVERS=$(get_group_servers "$GROUP" "$groups_file")
        if echo "$GROUP_SERVERS" | grep -qx "$SERVER"; then
          GROUPS="$GROUPS $GROUP"
        fi
      done

      if [ -n "$GROUPS" ]; then
        echo "**Groups:** $(echo $GROUPS | sed 's/^ //')"
        echo ""
      fi

      echo "---"
      echo ""
    done
  fi

  # Document all groups
  echo "## Available Groups"
  echo ""

  if [ -z "$all_groups" ]; then
    echo "No groups defined in the configuration file."
    echo ""
  else
    for GROUP in $all_groups; do
      GROUP_SERVERS=$(get_group_servers "$GROUP" "$groups_file")

      echo "### $GROUP"
      echo ""
      echo "**Servers in this group:**"
      echo ""

      if [ -z "$GROUP_SERVERS" ]; then
        echo "No servers in this group."
      else
        for SERVER in $(echo "$GROUP_SERVERS" | sort); do
          SERVER_DEF=$(get_server_definition "$SERVER" "$servers_file")
          if [ -n "$SERVER_DEF" ] && [ "$SERVER_DEF" != "null" ]; then
            SERVER_DESC=$(echo "$SERVER_DEF" | jq -r '.description // "No description"')
            echo "- **$SERVER**: $SERVER_DESC"
          else
            echo "- **$SERVER**: *Server definition not found*"
          fi
        done
      fi

      echo ""
      echo "---"
      echo ""
    done
  fi

  # Add instructions section
  echo "## Usage Instructions"
  echo ""
  echo "### Basic Commands"
  echo ""
  echo "```bash"
  echo "# List all available servers and groups"
  echo "mcpt list"
  echo ""
  echo "# Run a specific server"
  echo "mcpt run server_name"
  echo ""
  echo "# Run all servers in a group"
  echo "mcpt run group_name"
  echo ""
  echo "# Get information about a server"
  echo "mcpt info server_name"
  echo ""
  echo "# Add a server to Claude MCP"
  echo "mcpt claude server_name [--project|--global]"
  echo ""
  echo "# Add a server to Cursor MCP"
  echo "mcpt cursor server_name [--project|--global]"
  echo ""
  echo "# Setup environment variables for a server"
  echo "mcpt setup server_name"
  echo "```"
  echo ""
  echo "### Interactive Mode"
  echo ""
  echo "Launch the interactive menu with:"
  echo "```bash"
  echo "mcpt interactive"
  echo "```"
}
# Function to create a custom group file
create_custom_group() {
  local group_name="$1"
  local server_list="$2"
  local output_file="$SCRIPT_DIR/custom_groups/${group_name}.json"

  # Ensure directory exists with proper permissions
  mkdir -p "$SCRIPT_DIR/custom_groups"
  chmod 755 "$SCRIPT_DIR/custom_groups"

  # Validate input is a valid JSON array
  if ! echo "$server_list" | jq empty >/dev/null 2>&1; then
    echo "Error: Invalid JSON array provided for server list"
    return 1
  fi

  # Validate that each server in the list exists in our config
  local invalid_servers=()
  local server

  for server in $(echo "$server_list" | jq -r '.[]'); do
    # Need to ensure JSON_FILE is accessible or passed
    if ! jq -e --arg server "$server" '.servers[$server]' "$JSON_FILE" >/dev/null 2>&1; then
      invalid_servers+=("$server")
    fi
  done

  if [ ${#invalid_servers[@]} -gt 0 ]; then
    echo "Warning: The following servers in the group do not exist in your config:"
    for invalid in "${invalid_servers[@]}"; do
      echo "  - $invalid"
    done

    # Confirm continuation
    read -p "Do you want to create the group anyway? (y/n) [n]: " continue_anyway
    if [ "$continue_anyway" != "y" ]; then
      echo "Group creation aborted."
      return 1
    fi
  fi

  # Create the output file with proper formatting via jq
  if ! echo "{\"servers\": $server_list}" | jq . > "$output_file"; then
    echo "Error: Failed to create custom group file"
    return 1
  fi

  echo "Created custom group file: $output_file"

  # Show the group content for confirmation
  echo "Group contains the following servers:"
  jq -r '.servers[]' "$output_file" | sort | sed 's/^/  - /'

  return 0
}