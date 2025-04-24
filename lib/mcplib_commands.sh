#!/usr/bin/env bash

# MCP Tool - Command implementations
# This file contains the main logic for handling different mcptool commands.

# Ensure core functions are available if needed (adjust sourcing as necessary)
# source "$(dirname "${BASH_SOURCE[0]}")/mcplib_core.sh"
# Unified function to add a server to various backends/files
# Usage: add_server <server_name> [--skip-validation] <target_options...>
# --skip-validation is primarily for internal use when adding groups
add_server() {
  local server_name="$1"
  shift # Remove server_name from args

  # NEW: Optional argument to skip validation (used internally for groups)
  local skip_validation=false
  if [ "$1" = "--skip-validation" ]; then
      skip_validation=true
      shift # Consume the flag
  fi

  local backend=""
  local target_file=""
  local scope="project" # Default scope
  local overwrite=false

  # Check for target keyword/filename
  if [ $# -eq 0 ]; then
    echo "Error: The 'add' command requires a target (claude, cursor, or <filename.json>)." >&2
    # usage function needs to be available or its content replicated/adapted
    echo "Usage: mcptool add <server> <target> [options]" # Assuming mcptool is the command name
    echo "Example: mcptool add $server_name claude --user"
    echo "Example: mcptool add $server_name myconfig.json --overwrite"
    echo "To view the server's JSON definition, use: mcptool json $server_name"
    return 1
  fi

  local target_arg="$1"
  shift # Consume target argument

  # Determine backend/target file based on target_arg
  case "$target_arg" in
    claude)
      backend="claude"
      ;;
    cursor)
      backend="cursor"
      ;;
    *.json)
      backend="json"
      target_file="$target_arg"
      ;;
    *)
      echo "Error: Invalid target '$target_arg'. Must be 'claude', 'cursor', or a filename ending in '.json'." >&2
      return 1
      ;;
  esac

  # Parse remaining options (flags)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        scope="project"
        shift
        ;;
      --user) # Renamed from --global
        scope="user"
        shift
        ;;
      --overwrite)
        overwrite=true
        shift
        ;;
      *)
        echo "Error: Unknown option '$1' for add $backend target." >&2
        # TODO: Add more detailed help based on backend?
        return 1
        ;;
    esac
  done

  # Validate scope option applicability
  if [[ "$scope" == "user" && "$backend" != "cursor" ]]; then
      echo "Warning: --user scope is only applicable for the 'cursor' target. Ignored." >&2
      # Reset scope if misused, or let the backend handle it if needed
      # scope="project"
  fi
   # Validate overwrite option applicability
  if [[ "$overwrite" = true && "$backend" == "claude" ]]; then
      echo "Warning: --overwrite option is not applicable for the 'claude' target. Ignored." >&2
      overwrite=false # Claude doesn't overwrite files
  fi

  # Proceed with adding to the specified target
  echo "Attempting to add server '$server_name' to target..."

  # Dispatch to the appropriate backend function
  # Needs access to add_to_claude, add_to_cursor (from mcplib_add_targets.sh)
  # Needs access to core functions like get_validated_server_definition, ensure_env_vars_set
  # Needs access to global vars like SERVERS_FILE
  if [ -z "$backend" ]; then
      echo "Error: No backend determined (this is likely a bug)." >&2
      return 1
  fi
  case "$backend" in
    claude)
      # Assumes add_to_claude is sourced/available
      add_to_claude "$server_name" "$SERVERS_FILE" "$scope" # Pass user scope
      ;;
    cursor)
      # Assumes add_to_cursor is sourced/available
      add_to_cursor "$server_name" "$SERVERS_FILE" "$scope" "$overwrite" # Pass user scope
      ;;
    json)
      if [ -z "$target_file" ]; then
          echo "Error: No target file specified for JSON backend." >&2
          return 1
      fi

      # Handle overwrite flag
      if [ "$overwrite" = true ]; then
          if [ -f "$target_file" ]; then
              # echo "Overwriting existing file: $target_file" # Verbose
              rm -f "$target_file"
              if [ $? -ne 0 ]; then
                  echo "Error: Failed to remove existing file for overwrite." >&2
                  return 1
              fi
          fi
      fi

      # echo "Adding server '$server_name' to JSON file: $target_file" # Verbose

      # Validate and get server definition from the source SERVERS_FILE
      # Assumes get_validated_server_definition is sourced/available
      local server_json
      server_json=$(get_validated_server_definition "$server_name" "$SERVERS_FILE")
      if [ $? -ne 0 ]; then
        return 1 # Error message already printed by helper
      fi

      # Check required environment variables (non-interactive)
      # Assumes ensure_env_vars_set is sourced/available
      ensure_env_vars_set "$server_name" "$SERVERS_FILE"
      local exit_code=$?

      if [ $exit_code -eq 2 ]; then # Error finding server
          echo "Error: Could not find server '$server_name' to check env vars." >&2
          return 1
      elif [ $exit_code -eq 1 ]; then # Missing env vars
          echo "Skipping addition of $server_name to $target_file due to missing environment variables." >&2
          return 1
      fi
      # Exit code 0 means vars are set or were set successfully

      # Ensure target directory exists
      local target_dir
      target_dir=$(dirname "$target_file")
      if ! mkdir -p "$target_dir"; then
        echo "Error: Could not create target directory $target_dir" >&2
        return 1
      fi

      # Check target file status and prepare it
      local temp_json_file
      temp_json_file=$(mktemp)
      chmod 600 "$temp_json_file"
      # Register cleanup trap here if not done globally
      trap 'rm -f "$temp_json_file" 2>/dev/null || true' EXIT INT TERM

      if [ ! -f "$target_file" ]; then
        echo '{ "servers": {} }' > "$target_file" # Use "servers" key for generic JSON
        chmod 644 "$target_file"
        # echo "Created new JSON configuration file at $target_file" # Verbose
      elif ! jq empty "$target_file" 2>/dev/null; then
        local backup_file="${target_file}.bak.$(date +%Y%m%d%H%M%S)"
        echo "Error: Target file $target_file is not valid JSON. Cannot merge." >&2
        echo "Backing up invalid file to $backup_file"
        cp "$target_file" "$backup_file" || { echo "Backup failed!"; return 1; } # Exit if backup fails
        echo '{ "servers": {} }' > "$target_file" # Reset
        # echo "Created new JSON configuration file at $target_file" # Verbose
      fi

      # Ensure "servers" key exists
       if ! jq -e '.servers' "$target_file" >/dev/null 2>&1; then
         # Use sponge or temp file for reliable update
         jq '. + {"servers": {}}' "$target_file" > "$temp_json_file" && mv "$temp_json_file" "$target_file" || { echo "Failed to add servers key"; return 1; }
         # Re-check after attempting fix
         if ! jq -e '.servers' "$target_file" >/dev/null 2>&1; then
             echo "Error: Failed to ensure 'servers' key exists in $target_file" >&2
             return 1
         fi
       fi

      # Process env vars in definition for ${VAR} substitution
      # Assumes process_env_vars_json or similar logic is available
      local processed_server_json
      processed_server_json=$(echo "$server_json" | jq '.') # Start with original JSON
      if echo "$server_json" | jq -e 'has("env")' >/dev/null 2>&1; then
        while read -r key_value; do
          [ -z "$key_value" ] && continue
          local key="${key_value%%=*}"
          local value="${key_value#*=}"
          if [[ -n "$key" && -n "$value" ]]; then
            local evaluated_value
            # Safer env var expansion
            if [[ "$value" =~ ^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$ ]]; then
                 var_name=$(echo "$value" | sed 's/^\${//; s/}$//')
                 evaluated_value="${!var_name}"
            else
                 evaluated_value=$(eval printf '%s' "$value" 2>/dev/null || echo "$value")
            fi
            processed_server_json=$(echo "$processed_server_json" | jq --arg key "$key" --arg value "$evaluated_value" '.env[$key] = $value')
          fi
        done < <(echo "$server_json" | jq -r '.env | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null || echo "")
      fi

      # Merge the definition into the "servers" object using temp file
      if ! jq --arg server "$server_name" --argjson definition "$processed_server_json" \
         '.servers[$server] = $definition' "$target_file" > "$temp_json_file"; then
        echo "Error: Failed to merge server definition into $target_file. Check JSON format." >&2
        # rm -f "$temp_json_file" # Cleanup handled by trap
        return 1
      fi

      # Verify and move
      if ! jq empty "$temp_json_file" 2>/dev/null; then
        echo "Error: Generated configuration in temp file is not valid JSON." >&2
        # rm -f "$temp_json_file" # Cleanup handled by trap
        return 1
      fi
      if mv "$temp_json_file" "$target_file"; then
        echo "Successfully added/updated $server_name in $target_file" # Keep this one

        # Validation step removed as per user request
        # rm -f "$temp_json_file" # Cleanup handled by trap
        return 0
      else
        echo "Error: Failed to write updated configuration to $target_file" >&2
        # rm -f "$temp_json_file" # Ensure cleanup even if mv fails
        return 1
      fi
      ;;
    *)
      echo "Error: Unknown backend '$backend'" >&2
      return 1
      ;;
  esac
}
# Command: list
cmd_list() {
  # Needs access to ALL_SERVERS, ALL_GROUPS (global or passed)
  echo "Available servers:"
  if [ -n "$ALL_SERVERS" ]; then
    echo "$ALL_SERVERS" | sort | sed 's/^/  /'
  else
    echo "  No servers defined"
  fi

  echo ""
  echo "Available groups:"
  if [ -n "$ALL_GROUPS" ]; then
    echo "$ALL_GROUPS" | sort | sed 's/^/  /'
  else
    echo "  No groups defined"
  fi
  exit 0
}

# Command: run
# Args: $1 = target (server or group name), $2 = RUN_BACKGROUND (true/false)
cmd_run() {
  local target="$1"
  local run_bg="$2"
  local server_list
  local server_array=()
  # Needs access to ALL_SERVERS, ALL_GROUPS, SERVERS_FILE, GROUPS_FILE (global or passed)
  # Needs access to functions: get_group_servers, get_server_definition, ensure_env_vars_set, process_env_vars (core)
  # Needs access to functions: run_in_background, run_in_separate_terminals (run_modes)

  if echo "$ALL_GROUPS" | grep -qx "$target"; then
    # Target is a group
    while IFS= read -r line; do [[ -n "$line" ]] && server_array+=("$line"); done < <(get_group_servers "$target" "$GROUPS_FILE")
    server_list=$(printf "%s " "${server_array[@]}")
    server_list="${server_list% }" # Remove trailing space

    if [ ${#server_array[@]} -eq 0 ]; then
      echo "Warning: Group '$target' exists but contains no servers."
      exit 0
    fi

    # Check env vars for all servers in group *before* starting any
    local group_env_ok=true
    for server in "${server_array[@]}"; do
        ensure_env_vars_set "$server" "$SERVERS_FILE" # Check and potentially prompt
        local exit_code=$?
        if [ $exit_code -ne 0 ]; then
            group_env_ok=false
            # ensure_env_vars_set already printed warnings/errors
        fi
    done

    if [ "$group_env_ok" = false ]; then
        echo "One or more servers in group '$target' have missing environment variables. Aborting run." >&2
        exit 1
    fi

    # Environment variables seem okay, proceed with running
    if [ "$run_bg" = true ]; then
        echo "Running group '$target' servers in background..."
        run_in_background "$server_list" # From mcplib_run_modes.sh
    else
        echo "Running group '$target' servers in separate terminals..."
        run_in_separate_terminals "$server_list" # From mcplib_run_modes.sh
    fi
    exit $?
  elif echo "$ALL_SERVERS" | grep -qx "$target"; then
    # Target is a single server
    server_list="$target"
    server_array=("$target")

    # Check required env vars first (interactive prompt handled within)
    ensure_env_vars_set "$target" "$SERVERS_FILE" # From mcplib_core.sh
    local exit_code=$?
    if [ $exit_code -eq 2 ]; then # Server not found error
        # Error already printed by ensure_env_vars_set
        exit 1
    elif [ $exit_code -eq 1 ]; then # Missing env vars, user likely said no to prompt
        echo "Skipping run of $target due to missing environment variables." >&2
        exit 1
    fi
    # Exit code 0 means OK

    if [ "$run_bg" = true ]; then
        run_in_background "$server_list" # From mcplib_run_modes.sh
        exit 0
    else
        # Run single server in foreground
        local server_def server_cmd server_args server_desc server_env env_array args_array
        server_def=$(get_server_definition "$target" "$SERVERS_FILE") # From mcplib_core.sh
        server_cmd=$(echo "$server_def" | jq -r '.command')
        # Correctly handle args array
        args_array=()
        while IFS= read -r line; do args_array+=("$line"); done < <(echo "$server_def" | jq -r '.args[]?' 2>/dev/null)
        server_desc=$(echo "$server_def" | jq -r '.description // "No description"')
        # Get env vars as KEY=VALUE array for `env` command
        env_array=()
        while IFS= read -r key_value; do
            [ -z "$key_value" ] && continue
            local key="${key_value%%=*}"
            local value="${key_value#*=}"
            local evaluated_value
            if [[ "$value" =~ ^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$ ]]; then
                 var_name=$(echo "$value" | sed 's/^\${//; s/}$//')
                 evaluated_value="${!var_name}"
            else
                 evaluated_value=$(eval printf '%s' "$value" 2>/dev/null || echo "$value")
            fi
            env_array+=("$key=$evaluated_value")
        done < <(echo "$server_def" | jq -r '.env | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null || echo "")


        echo "Starting server: $target"
        echo "Description: $server_desc"
        # Display command for user info, but execute using arrays
        local display_args=$(printf '%q ' "${args_array[@]}")
        local display_env=$(printf '%q ' "${env_array[@]}")
        echo "Command: env ${display_env}${server_cmd} ${display_args}"
        echo "-----------------------------------"

        # Execute command directly using arrays
        if ! env "${env_array[@]}" "$server_cmd" "${args_array[@]}"; then
            echo "Error: Failed to start server $target with exit code $?" >&2
            exit 1
        fi
        exit 0 # Success
    fi
  else
    echo "Error: Unknown server or group: $target" >&2
    # Needs usage function or similar message
    echo "Use 'mcptool list' to see available servers and groups" >&2
    exit 1
  fi
}

# Command: info
# Args: $1 = target (server or group name), $2 = VERBOSE (true/false)
cmd_info() {
    local target="$1"
    local verbose="$2"
    local server_array=()
    # Needs access to ALL_SERVERS, ALL_GROUPS, SERVERS_FILE, GROUPS_FILE (global or passed)
    # Needs access to functions: get_group_servers, get_server_definition (core)

    if echo "$ALL_GROUPS" | grep -qx "$target"; then
        # Target is a group
        while IFS= read -r line; do [[ -n "$line" ]] && server_array+=("$line"); done < <(get_group_servers "$target" "$GROUPS_FILE")

        if [ ${#server_array[@]} -eq 0 ]; then
            echo "Warning: Group '$target' exists but contains no servers."
            exit 0
        fi

        if [ "$verbose" = false ]; then
            echo "Group: $target"
            echo "Servers in this group:"
            for server in "${server_array[@]}"; do
              local server_def server_desc
              server_def=$(get_server_definition "$server" "$SERVERS_FILE")
              if [ -n "$server_def" ] && [ "$server_def" != "null" ]; then
                server_desc=$(echo "$server_def" | jq -r '.description // "No description"')
                echo "  - $server: $server_desc"
              else
                echo "  - $server: WARNING - Server not defined in config"
              fi
            done
            exit 0
        else
            # Verbose group info: process each server individually
            echo "--- Group: $target ---"
            for server in "${server_array[@]}"; do
                cmd_info "$server" true # Call recursively for each server in verbose mode
            done
            echo "--- End Group: $target ---"
            exit 0
        fi
    elif echo "$ALL_SERVERS" | grep -qx "$target"; then
        # Target is a single server
        local server_def server_cmd server_args server_desc
        server_def=$(get_server_definition "$target" "$SERVERS_FILE")
        if [ -z "$server_def" ] || [ "$server_def" = "null" ]; then
            echo "Error: Server '$target' definition not found." >&2
            exit 1
        fi

        server_cmd=$(echo "$server_def" | jq -r '.command')
        # Correctly handle args array for display
        local args_display=""
        args_array=()
        while IFS= read -r line; do args_array+=("$line"); done < <(echo "$server_def" | jq -r '.args[]?' 2>/dev/null)
        args_display=$(printf '%q ' "${args_array[@]}")

        server_desc=$(echo "$server_def" | jq -r '.description // "No description"')

        echo "-----------------------------------"
        echo "Server: $target"
        echo "Description: $server_desc"
        echo "Command: $server_cmd $args_display" # Display quoted args

        if [ "$verbose" = true ]; then
            echo ""
            echo "Environment Variables (Templates):"
            local env_vars=()
            while IFS= read -r line; do env_vars+=("$line"); done < <(jq -r '(.env // {}) | keys[]?' <<< "$server_def")
            if [ ${#env_vars[@]} -gt 0 ] && [ -n "${env_vars[0]}" ]; then
                for var in "${env_vars[@]}"; do
                  [ -z "$var" ] && continue
                  local val=$(jq -r --arg var "$var" '(.env // {})[$var]' <<< "$server_def")
                  echo "  $var = $val"
                done
            else
                echo "  None"
            fi

            echo ""
            echo "Required Environment Variables:"
            local required_envs=()
            while IFS= read -r line; do required_envs+=("$line"); done < <(jq -r '(.required_env // [])[]?' <<< "$server_def")
            if [ ${#required_envs[@]} -gt 0 ] && [ -n "${required_envs[0]}" ]; then
                for reqvar in "${required_envs[@]}"; do
                  [ -z "$reqvar" ] && continue
                  echo "  $reqvar"
                done
            else
                echo "  None"
            fi
        fi
        echo "-----------------------------------"
        exit 0
    else
        echo "Error: Unknown server or group: $target" >&2
        # Needs usage function or similar message
        echo "Use 'mcptool list' to see available servers and groups" >&2
        exit 1
    fi
}


# Command: json
# Args: $1 = target (server or group name)
cmd_json() {
    local target="$1"
    # Needs access to ALL_SERVERS, ALL_GROUPS, SERVERS_FILE, GROUPS_FILE (global or passed)
    # Needs access to functions: get_group_servers, get_server_definition (core)

    if echo "$ALL_GROUPS" | grep -qx "$target"; then
        # Target is a group
        local group_servers server_def first=true
        group_servers=$(get_group_servers "$target" "$GROUPS_FILE")

        echo "[" # Start JSON array
        for server in $group_servers; do
            # Skip empty server names if any somehow get through
            [ -z "$server" ] && continue
            server_def=$(get_server_definition "$server" "$SERVERS_FILE")
            if [ -n "$server_def" ] && [ "$server_def" != "null" ]; then
                if [ "$first" = true ]; then
                    first=false
                else
                    echo "," # Add comma before subsequent entries
                fi
                # Ensure valid JSON output, even if server_def isn't perfectly formatted
                echo "$server_def" | jq -c '.' # Output compact JSON
            fi
        done
        echo "]" # End JSON array
        exit 0
    elif echo "$ALL_SERVERS" | grep -qx "$target"; then
        # Target is a single server
        local server_def=$(get_server_definition "$target" "$SERVERS_FILE")
         if [ -n "$server_def" ] && [ "$server_def" != "null" ]; then
             echo "$server_def" | jq -c '.' # Output compact JSON
             exit 0
         else
             echo "Error: Server '$target' definition not found or invalid." >&2
             exit 1
         fi
    else
        echo "Error: Unknown server or group: $target" >&2
        # Needs usage function or similar message
        echo "Use 'mcptool list' to see available servers and groups" >&2
        exit 1
    fi
}

# Command: docs
cmd_docs() {
  # Needs generate_documentation from mcplib_generators.sh
  # Needs access to SERVERS_FILE, GROUPS_FILE (global or passed)
  generate_documentation "$SERVERS_FILE" "$GROUPS_FILE"
  exit 0
}

# Command: interactive
cmd_interactive() {
  # Needs interactive_menu from mcplib_ui.sh
  # Needs access to ALL_SERVERS, ALL_GROUPS, SCRIPT_DIR, VERSION, JSON_FILE (consider passing these)
  # JSON_FILE might need to be derived or passed explicitly if not global
  # $0 within interactive_menu needs to be replaced with the actual script path
  interactive_menu
  exit 0
}

# Command: autoloader
cmd_autoloader() {
  # Needs generate_autoloader from mcplib_generators.sh
  # Needs access to SCRIPT_DIR (global or passed)
  local autoloader_file="$HOME/.mcp_autoloader.zsh"
  # Pass the full path to the main script
  local main_script_path="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" # Adjust if this file is sourced differently
  generate_autoloader "$autoloader_file" "$main_script_path"
  exit 0
}

# Command: help
# Args: $1 = command name to get help for
cmd_help() {
  local help_target="$1"
  # Needs display_detailed_help from mcplib_ui.sh
  # Needs access to VERSION, JSON_FILE, SERVERS_FILE (global or passed)
  display_detailed_help "$help_target"
  # exit 0 # display_detailed_help handles exit
}

# Command: setup (Placeholder, as it was removed but referenced in interactive menu)
# Args: $1 = target server name
cmd_setup() {
    local target="$1"
    # Needs setup_wizard from mcplib_core.sh
    # Needs access to ALL_SERVERS, SERVERS_FILE (global or passed)
    # Verify server exists
    if ! echo "$ALL_SERVERS" | grep -qx "$target"; then
      echo "Error: Unknown server: $target" >&2
      # Needs usage function or similar message
      echo "Use 'mcptool list' to see available servers" >&2
      exit 1
    fi
    setup_wizard "$target" "$SERVERS_FILE"
    exit 0
}