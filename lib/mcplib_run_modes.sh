#!/usr/bin/env bash

# MCP Tool - 'run' command mode implementations
# This file contains functions for running servers in different modes,
# such as background (detached) or in separate terminal windows.

# Ensure core functions are available if needed (adjust sourcing as necessary)
# source "$(dirname "${BASH_SOURCE[0]}")/mcplib_core.sh"
# Function to run servers in background (detached)
run_in_background() {
  local server_list="$1"
  local log_dir="$SCRIPT_DIR/logs" # SCRIPT_DIR needs to be globally available or passed
  local server_array=()

  # Parse space-separated list into array
  read -ra server_array <<< "$server_list"

  # Ensure log directory exists with proper permissions
  mkdir -p "$log_dir"
  chmod 755 "$log_dir"

  echo "Running servers in background mode..."

  for SERVER in "${server_array[@]}"; do
    # Skip empty entries
    [ -z "$SERVER" ] && continue

    # Validate server exists
    # Need to ensure JSON_FILE is accessible or passed
    if ! jq -e --arg server "$SERVER" '.servers[$server]' "$JSON_FILE" >/dev/null 2>&1; then
      echo "Error: Server '$SERVER' not found in config. Skipping."
      continue
    fi

    # Get command and args
    # Need to ensure JSON_FILE and process_env_vars are accessible or passed
    SERVER_CMD=$(jq -r --arg server "$SERVER" '.servers[$server].command' "$JSON_FILE")
    SERVER_ARGS=$(jq -r --arg server "$SERVER" '.servers[$server].args | join(" ")' "$JSON_FILE")
    SERVER_ENV=$(process_env_vars "$SERVER" "$JSON_FILE")
    SERVER_DESC=$(jq -r --arg server "$SERVER" '.servers[$server].description // "No description"' "$JSON_FILE")

    # Create timestamped log file name to avoid collisions
    local timestamp=$(date +%Y%m%d_%H%M%S)
    # Append a random suffix to prevent rare collisions
    local random_suffix=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6)
    LOG_FILE="$log_dir/${SERVER}_${timestamp}_${random_suffix}.log"
    PID_FILE="$log_dir/${SERVER}_${timestamp}_${random_suffix}.pid"

    echo "Starting $SERVER in background..."
    echo "Description: $SERVER_DESC"
    echo "Command: $SERVER_ENV $SERVER_CMD $SERVER_ARGS"
    echo "Logs: $LOG_FILE"
    echo "PID File: $PID_FILE"

    # Create a wrapper script to allow nohup and proper process isolation
    local run_script=$(mktemp -t "mcptool_bg_${SERVER}_XXXXXXXX")
    chmod 700 "$run_script"

    {
      echo "#!/bin/bash"
      echo "# Auto-generated runner for $SERVER"
      echo ""
      echo "# Redirect all output to log file"
      echo "exec >> \"$LOG_FILE\" 2>&1"
      echo ""
      echo "echo \"=== Starting $SERVER at $(date) ===\""
      echo "echo \"Command: $SERVER_ENV $SERVER_CMD $SERVER_ARGS\""
      echo "echo \"===================================\""
      echo ""
      echo "# Execute actual command"
      echo "$SERVER_ENV $SERVER_CMD $SERVER_ARGS"
      echo ""
      echo "exit_code=\$?"
      echo "echo \"=== $SERVER exited with code \$exit_code at $(date) ===\""
      echo "rm \"$run_script\" 2>/dev/null || true"
    } > "$run_script"

    # Start the process with nohup to make it immune to hangups
    nohup setsid bash "$run_script" >/dev/null 2>&1 &

    # Capture PID of the setsid process (parent of the actual server)
    local server_pid=$!
    echo "$server_pid" > "$PID_FILE"
    echo "Started $SERVER with parent PID: $server_pid"

    # Add a symlink to latest PID and log files for convenience
    ln -sf "$PID_FILE" "$log_dir/${SERVER}.pid.latest"
    ln -sf "$LOG_FILE" "$log_dir/${SERVER}.log.latest"

    # Small delay to prevent overwhelming the system
    sleep 0.5
  done

  echo "All servers have been started in background mode."
  echo "Logs are available in: $log_dir"
  echo "Use 'ps' to check running processes or check PID files in $log_dir"
  echo "To view latest log: less ${log_dir}/server_name.log.latest"
  echo "To stop a server: kill \$(cat ${log_dir}/server_name.pid.latest)"
  return 0
}

# Function to run servers in separate terminal windows
run_in_separate_terminals() {
  local server_list="$1"
  local server_array=()

  # Parse space-separated list into array
  read -ra server_array <<< "$server_list"

  # Set up trap to ensure cleanup of temporary scripts
  local temp_scripts=()
  trap 'rm -f "${temp_scripts[@]}" 2>/dev/null' EXIT INT TERM

  for SERVER in "${server_array[@]}"; do
    # Skip empty entries
    [ -z "$SERVER" ] && continue

    # Validate server exists
    # Need to ensure JSON_FILE is accessible or passed
    if ! jq -e --arg server "$SERVER" '.servers[$server]' "$JSON_FILE" >/dev/null 2>&1; then
      echo "Error: Server '$SERVER' not found in config. Skipping."
      continue
    fi

    # Get command and args
    # Need to ensure JSON_FILE and process_env_vars are accessible or passed
    SERVER_CMD=$(jq -r --arg server "$SERVER" '.servers[$server].command' "$JSON_FILE")
    SERVER_ARGS=$(jq -r --arg server "$SERVER" '.servers[$server].args | join(" ")' "$JSON_FILE")
    SERVER_ENV=$(process_env_vars "$SERVER" "$JSON_FILE")

    # Create a temporary script to run the command
    TEMP_SCRIPT=$(mktemp -t "mcptool_${SERVER}_XXXXXXXX")
    temp_scripts+=("$TEMP_SCRIPT")

    {
      echo "#!/bin/bash"
      echo "echo \"Starting server: $SERVER\""
      echo "echo \"Command: $SERVER_ENV $SERVER_CMD $SERVER_ARGS\""
      echo "echo \"Press Ctrl+C to stop or close this window\""
      echo "echo \"-----------------------------------\""
      echo "$SERVER_ENV $SERVER_CMD $SERVER_ARGS"
      echo "echo \"Server $SERVER stopped.\""
      echo "echo \"Return code: \$?\""
      echo "read -p \"Press Enter to close this window...\" dummy"
      # Self-delete the script for better cleanup
      echo "rm \"$TEMP_SCRIPT\" 2>/dev/null || true"
    } > "$TEMP_SCRIPT"

    chmod +x "$TEMP_SCRIPT"

    # Open in a new terminal window based on OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS with proper escaping
      osascript -e "tell application \"Terminal\" to do script \"'$TEMP_SCRIPT'\""
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
      # Linux - try different terminal emulators
      if command -v gnome-terminal &> /dev/null; then
        gnome-terminal -- bash -c "'$TEMP_SCRIPT'"
      elif command -v xterm &> /dev/null; then
        xterm -e "bash '$TEMP_SCRIPT'" &
      elif command -v konsole &> /dev/null; then
        konsole -e "bash '$TEMP_SCRIPT'" &
      else
        echo "Error: Could not find a suitable terminal emulator."
        continue
      fi
    else
      echo "Error: Unsupported operating system for terminal windows."
      continue
    fi

    echo "Launched server: $SERVER in a new terminal window"

    # Small delay to prevent overwhelming the system
    sleep 0.5
  done

  echo "All servers have been launched in separate terminal windows."
  return 0
}