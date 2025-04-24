#!/usr/bin/env bash

# MCP Tool - A unified command-line utility for managing Model Context Protocol (MCP) servers
# This script combines the functionality of both enhanced and interactive versions

# Exit on error, but allow for proper error handling
set -o errexit
set -o pipefail

# Set up paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$ROOT_DIR/lib"
CONFIG_DIR="$ROOT_DIR/config"

# Source common functions
source "$LIB_DIR/mcplib_core.sh"
source "$LIB_DIR/mcplib_ui.sh"
source "$LIB_DIR/mcplib_generators.sh"
source "$LIB_DIR/mcplib_run_modes.sh"
source "$LIB_DIR/mcplib_add_targets.sh"
source "$LIB_DIR/mcplib_commands.sh"

# Default paths for configuration files
DEFAULT_SERVERS_FILE="$CONFIG_DIR/servers.json"
DEFAULT_GROUPS_FILE="$CONFIG_DIR/groups.json"

# Allow override via environment variables
SERVERS_FILE="${MCP_SERVERS_FILE:-$DEFAULT_SERVERS_FILE}"
GROUPS_FILE="${MCP_GROUPS_FILE:-$DEFAULT_GROUPS_FILE}"

VERSION="1.2.0"  # Added support for separate servers.json and groups.json
VERBOSE=false

# 'add' target functions (add_to_claude, add_to_cursor) moved to lib/mcplib_add_targets.sh

# add_server function moved to lib/mcplib_commands.sh

# Run mode functions moved to lib/mcplib_run_modes.sh
# create_custom_group moved to lib/mcplib_generators.sh
# UI functions moved to lib/mcplib_ui.sh

# Main execution starts here

# Check dependencies
check_dependencies

# Process command line options for file paths
for arg in "$@"; do
  case "$arg" in
    --servers-file=*)
      SERVERS_FILE="${arg#*=}"
      ;;
    --groups-file=*)
      GROUPS_FILE="${arg#*=}"
      ;;
  esac
done

# Check for servers file
if [ ! -f "$SERVERS_FILE" ] && [ ! -f "${SERVERS_FILE%.json}.yaml" ] && [ ! -f "${SERVERS_FILE%.json}.yml" ]; then
  echo "Error: Servers file not found at '$SERVERS_FILE' or as YAML"
  echo "Ensure the file exists or specify a custom path with --servers-file=<path>"
  echo "or set the MCP_SERVERS_FILE environment variable."
  exit 1
fi

# Check for groups file
if [ ! -f "$GROUPS_FILE" ] && [ ! -f "${GROUPS_FILE%.json}.yaml" ] && [ ! -f "${GROUPS_FILE%.json}.yml" ]; then
  echo "Error: Groups file not found at '$GROUPS_FILE' or as YAML"
  echo "Ensure the file exists or specify a custom path with --groups-file=<path>"
  echo "or set the MCP_GROUPS_FILE environment variable."
  exit 1
fi

# Validate JSON file formats
if [ -f "$SERVERS_FILE" ] && ! jq empty "$SERVERS_FILE" 2>/dev/null; then
  echo "Error: $SERVERS_FILE is not a valid JSON file!"
  exit 1
fi

if [ -f "$GROUPS_FILE" ] && ! jq empty "$GROUPS_FILE" 2>/dev/null; then
  echo "Error: $GROUPS_FILE is not a valid JSON file!"
  exit 1
fi

# Show usage if no arguments provided
if [ $# -lt 1 ]; then
  usage
fi

# --- Determine Command and Command-Specific Args ---
COMMAND_ARG="$1"
shift || { usage; exit 1; } # Exit if no command provided

# Default values
TARGET="" # Server/group name or help topic
COMMAND=""
SCOPE="project" # Default scope for add cursor
STRICT_MODE=false # Currently unused?
VERBOSE=false
RUN_BACKGROUND=false
ADD_OPTIONS=() # Options specific to the 'add' command

case "$COMMAND_ARG" in
  run)
    COMMAND="run"
    TARGET="$1"
    shift || { echo "Error: Missing server or group name for 'run'"; usage; exit 1; }
    ;;
  info)
    COMMAND="info"
    TARGET="$1"
    shift || { echo "Error: Missing server or group name for 'info'"; usage; exit 1; }
    ;;
  json)
    COMMAND="json"
    TARGET="$1"
    shift || { echo "Error: Missing server or group name for 'json'"; usage; exit 1; }
    ;;
  add)
    COMMAND="add"
    TARGET="$1" # Server name for add
    shift || { echo "Error: Missing server name for 'add'"; usage; exit 1; }
    # Remaining args ($@) are parsed by add_server function later
    ADD_OPTIONS=("$@") # Capture all remaining args for add_server
    # Clear $@ so the general options loop doesn't process them
    set --
    ;;
  list)
    COMMAND="list"
    ;;
  docs)
    COMMAND="docs"
    ;;
  autoloader)
    COMMAND="autoloader"
    ;;
  interactive)
    COMMAND="interactive"
    ;;
  help)
    COMMAND="help"
    TARGET="$1" # Command name for help
    shift || { echo "Error: Missing command name for 'help'"; usage; exit 1; }
    ;;
  setup)
    COMMAND="setup"
    TARGET="$1" # Server name for setup
    shift || { echo "Error: Missing server name for 'setup'"; usage; exit 1; }
    ;;
  *)
    # If not a known command, check if it's a server/group name (implies 'info')
    TEMP_ALL_SERVERS=$(get_servers "$SERVERS_FILE") # Need to check before exporting
    TEMP_ALL_GROUPS=$(get_groups "$GROUPS_FILE")   # Need to check before exporting
    if echo "$TEMP_ALL_SERVERS" | grep -qx "$COMMAND_ARG" || echo "$TEMP_ALL_GROUPS" | grep -qx "$COMMAND_ARG"; then
      COMMAND="info"
      TARGET="$COMMAND_ARG" # The command itself is the target
      # No shift needed
    else
      echo "Error: Unknown command or target: $COMMAND_ARG" >&2
      usage # From mcplib_ui.sh
      exit 1
    fi
    ;;
esac

# --- Process General Options ---
# Process remaining arguments for general options like -v, --background
# Note: 'add' command options were captured earlier in ADD_OPTIONS
# Note: Options specific to 'add' (like --claude, --cursor, --json, --global, <file_path>)
# are handled within the add_server function itself using the remaining arguments ($@).
# ADD_OPTIONS already captured for 'add' command in the initial case block (lines 121-128).
# This loop processes only general options for other commands.
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    --background|--bg) # Allow --bg alias
      # Check if COMMAND is set and is 'run' before setting RUN_BACKGROUND
      if [ "$COMMAND" = "run" ]; then
          RUN_BACKGROUND=true
      # Avoid warning if COMMAND wasn't set (e.g., only general options given)
      # Only warn if a command *was* identified but isn't 'run'
      elif [ -n "$COMMAND" ] && [ "$COMMAND" != "run" ]; then
          echo "Warning: --background/--bg option is only valid for the 'run' command. Ignored." >&2
      fi
      shift
      ;;
    *)
      # Any remaining arguments are unknown general options.
      # The 'add' command's specific options were handled earlier.
      echo "Error: Unknown general option: $1" >&2
      usage
      exit 1
      ;;
  esac
done


# --- Load Config Data ---
# Get all servers and groups using our helper functions (needed globally by some commands)
# Moved TEMP check earlier, now assign to globals
ALL_SERVERS=$(get_servers "$SERVERS_FILE")
ALL_GROUPS=$(get_groups "$GROUPS_FILE")

# Check for config file errors after getting servers/groups
# Define JSON_FILE based on SERVERS_FILE existence (or pass explicitly) - Assuming servers file is primary for now
JSON_FILE="$SERVERS_FILE"
if [ ! -f "$JSON_FILE" ]; then
    # Attempt to find YAML alternative if primary JSON doesn't exist
    if [ -f "${SERVERS_FILE%.json}.yaml" ]; then
        JSON_FILE="${SERVERS_FILE%.json}.yaml"
    elif [ -f "${SERVERS_FILE%.json}.yml" ]; then
        JSON_FILE="${SERVERS_FILE%.json}.yml"
    fi
    # If still not found, error was already handled during file checks
fi


if [ -z "$ALL_SERVERS" ] && [ -z "$ALL_GROUPS" ]; then
  # get_servers/get_groups might have already printed errors for yq missing etc.
  echo "Error: No servers or groups found in configuration files." >&2
  echo "Servers file checked: $SERVERS_FILE (and YAML alternatives)" >&2
  echo "Groups file checked: $GROUPS_FILE (and YAML alternatives)" >&2
  exit 1
fi


# Redundant command determination and validation removed.
# This logic is now handled in the initial case block (lines 105-166).

# --- Special Handling for 'add group' ---
# If the command is 'add' and the target is a group, handle it here before general dispatch
if [ "$COMMAND" = "add" ] && echo "$ALL_GROUPS" | grep -qx "$TARGET"; then
  echo "Processing group '$TARGET' for add command..."
  group_servers=()
  while IFS= read -r server; do
      [[ -n "$server" ]] && group_servers+=("$server")
  done < <(get_group_servers "$TARGET" "$GROUPS_FILE")

  if [ ${#group_servers[@]} -eq 0 ]; then
    echo "Warning: Group '$TARGET' contains no servers. Nothing to add." >&2
    exit 0
  fi

  # --- Overwrite Handling for Group (Copied from original logic) ---
  perform_overwrite=false
  target_file_for_overwrite=""
  backend_for_overwrite=""
  temp_add_options=() # To store options without --overwrite

  # Peek into ADD_OPTIONS to find target and overwrite flag
  for option in "${ADD_OPTIONS[@]}"; do
      if [ "$option" = "--overwrite" ]; then
          perform_overwrite=true
      elif [[ "$option" == *.json ]]; then
           target_file_for_overwrite="$option"
           backend_for_overwrite="json"
           temp_add_options+=("$option")
      elif [ "$option" = "cursor" ]; then
           backend_for_overwrite="cursor"
           temp_add_options+=("$option")
      # Add claude if it ever supports file overwrite
      # elif [ "$option" = "claude" ]; then
      #    backend_for_overwrite="claude"
      #    temp_add_options+=("$option")
      else
          # Keep other options like --project, --user
          temp_add_options+=("$option")
      fi
  done

  # Determine target file for cursor if overwriting
  if [ "$backend_for_overwrite" = "cursor" ] && [ "$perform_overwrite" = true ]; then
      cursor_scope_group="project" # Use different var name to avoid scope clash
      for option in "${ADD_OPTIONS[@]}"; do
          if [ "$option" = "--user" ]; then
              cursor_scope_group="user"
              break
          fi
      done
      if [ "$cursor_scope_group" = "user" ]; then
          target_file_for_overwrite="${HOME:-~}/.cursor/mcp.json"
      else
          target_file_for_overwrite="./.cursor/mcp.json"
      fi
  fi

  # Perform overwrite *before* the loop if needed
  if [ "$perform_overwrite" = true ]; then
      if [ -n "$target_file_for_overwrite" ]; then
          target_dir_for_overwrite=$(dirname "$target_file_for_overwrite")
          if ! mkdir -p "$target_dir_for_overwrite"; then
              echo "Error: Could not create target directory '$target_dir_for_overwrite' for overwrite." >&2
              exit 1
          fi
          if [ -f "$target_file_for_overwrite" ]; then
              echo "Overwriting existing file for group '$TARGET': $target_file_for_overwrite"
              if ! rm -f "$target_file_for_overwrite"; then
                 echo "Error: Failed to remove existing file '$target_file_for_overwrite' for overwrite." >&2
                 exit 1
              fi
          fi
      elif [ "$backend_for_overwrite" = "claude" ]; then
           echo "Warning: --overwrite specified for 'claude' target, which is ignored." >&2
      else
          echo "Warning: --overwrite specified but could not determine target file. Overwrite skipped." >&2
      fi
      # Use options without --overwrite for individual calls
      ADD_OPTIONS=("${temp_add_options[@]}")
  fi
  # --- End Overwrite Handling ---

  overall_success=true
  for server in "${group_servers[@]}"; do
      echo "--- Adding server '$server' from group '$TARGET' ---"
      # Call add_server for each server in the group, skipping validation
      if ! add_server "$server" "--skip-validation" "${ADD_OPTIONS[@]}"; then
          overall_success=false
          echo "Error adding server '$server' from group '$TARGET'." >&2
          # break # Optional: Stop on first error
      fi
      echo "-------------------------------------------------"
  done

  if [ "$overall_success" = true ]; then
      echo "Successfully processed all servers in group '$TARGET'."
      exit 0
  else
      echo "One or more servers in group '$TARGET' failed to be added." >&2
      exit 1
  fi
fi # End of special 'add group' handling


# --- Main Command Dispatch ---

# Export variables needed by sourced functions (alternative to passing many args)
# Ensure required variables are exported for sourced scripts
export SERVERS_FILE GROUPS_FILE ALL_SERVERS ALL_GROUPS SCRIPT_DIR LIB_DIR VERSION JSON_FILE VERBOSE RUN_BACKGROUND ADD_OPTIONS TARGET

# Execute the appropriate command function from mcplib_commands.sh
# Note: The 'add' case below now only handles adding single servers
case "$COMMAND" in
  list)         cmd_list ;;
  run)          cmd_run "$TARGET" "$RUN_BACKGROUND" ;;
  info)         cmd_info "$TARGET" "$VERBOSE" ;;
  json)         cmd_json "$TARGET" ;;
  add)          add_server "$TARGET" "${ADD_OPTIONS[@]}" ;; # add_server handles its args
  docs)         cmd_docs ;;
  autoloader)   cmd_autoloader ;;
  interactive)  cmd_interactive ;;
  help)         cmd_help "$TARGET" ;;
  setup)        cmd_setup "$TARGET" ;; # Keep for interactive menu
  *)
    # This case should not be reached due to earlier validation
    echo "Internal Error: Unknown command '$COMMAND' reached main dispatch." >&2
    usage # From mcplib_ui.sh
    exit 1
    ;;
esac

exit $? # Exit with the status of the last executed command function
