#!/usr/bin/env bash

# MCP Tool - User Interface and Output functions
# This file contains functions related to displaying usage, help messages,
# and the interactive TUI menu.

# Ensure core functions are available if needed (adjust sourcing as necessary)
# source "$(dirname "${BASH_SOURCE[0]}")/mcplib_core.sh"
# Function to display detailed help for a specific command
display_detailed_help() {
  local cmd=$1
  echo "Detailed help for: $cmd"
  echo "---------------------------"
  case "$cmd" in
    list)
      echo "Usage: $0 list"
      echo "  Lists all available servers and groups defined in '$JSON_FILE'."
      echo "  Output format: Two sections showing all available servers and groups."
      ;;
    # Removed run-separate, background, validate commands
    run)
      echo "Usage: $0 run <server|group> [--background | --bg]"
      echo "  Runs the specified server or all servers within the specified group."
      echo "  Requires necessary environment variables to be set (check .env.mcp)."
      echo "  For a single server, runs in the current terminal unless --background is specified."
      echo "  For a group, automatically launches each server in a separate terminal unless --background is specified."
      echo "  --background or --bg: Runs the server(s) in detached background mode with logs."
      ;;
    info)
      echo "Usage: $0 info <server|group> [-v|--verbose]"
      echo "  Displays information about a specific server or group."
      echo "  For a server, shows description, command, and environment variables."
      echo "  For a group, lists the servers within the group."
      echo "  Use '-v' or '--verbose' with a group to show full details for each server in the group."
      ;;
    json)
      echo "Usage: $0 json <server|group>"
      echo "  Outputs the JSON definition for the specified server or an array of JSON definitions for the servers in the specified group."
      echo "  Output is in compact JSON format, suitable for piping to other commands."
      ;;
    # Removed claude and cursor commands
    add)
      echo "Usage: $0 add <server> <target> [options]"
      echo "  Adds the specified server definition from '$SERVERS_FILE' to the specified target."
      echo "  <target> must be one of: claude, cursor, <filename.json>"
      echo ""
      echo "  Targets:"
      echo "    claude           Adds to Claude MCP."
      echo "    cursor           Adds to Cursor config (.cursor/mcp.json)."
      echo "    <filename.json>  Adds to the specified JSON file (creates if needed)."
      echo ""
      echo "  Options:"
      echo "    --project        Use project-level scope for Cursor (./.cursor/mcp.json) [Default]."
      echo "    --user           Use user-level scope for Cursor (~/.cursor/mcp.json)."
      echo "    --overwrite      Overwrite the target file if it exists (for cursor or filename.json targets)."
      echo ""
      echo "  Checks for required environment variables before adding (prompts interactively)."
      echo "  Validates the target file after adding (for filename.json targets)."
      echo "  To view the server's JSON definition without adding, use: $0 json <server>"
      ;;
    docs)
      echo "Usage: $0 docs"
      echo "  Generates and displays comprehensive documentation for all servers."
      echo "  Output is in Markdown format."
      ;;
    interactive)
      echo "Usage: $0 interactive"
      echo "  Launches an interactive menu (requires 'dialog' utility) for selecting servers/groups and actions."
      echo "  Will attempt to install dialog if not found."
      echo "  Includes options to create custom groups and run servers in separate terminal windows."
      ;;
    # Removed setup command
    autoloader)
      echo "Usage: $0 autoloader"
      echo "  Generates a shell script ('$HOME/.mcp_autoloader.zsh' by default) to enable autocompletion for server/group names."
      echo "  You need to source this file in your shell configuration (e.g., .zshrc)."
      ;;
    # Removed version command
    help)
      echo "Usage: $0 help <command>"
      echo "  Displays detailed help for the specified command."
      ;;
    *)
      echo "Error: Unknown command '$cmd' for detailed help."
      usage # Show basic usage if help command is unknown
      exit 1
      ;;
  esac
  exit 0
}

usage() {
  echo "MCP Tool v$VERSION - Manage MCP Servers"
  echo ""
  echo "Usage: $0 <command> [target] [options]"
  echo ""
  echo "Commands:"
  echo "  list                   List servers and groups"
  echo "  run <target> [--bg]    Run a server or group. Groups run in separate terminals."
  echo "                         Use --background or --bg to run in detached background mode."
  echo "  add <server> <opts>    Add server definition to a required backend/file."
  echo "                         Target Options (required): --claude | --cursor [--global] | --json <file> | <file>"
  echo "  info <target> [-v]     Show info for a server or group (use -v for group details)"
  echo "  json <target>          Output server/group JSON definition"
  echo "  docs                   Show documentation for all servers"
  echo "  interactive            Launch interactive TUI menu (requires 'dialog')"
  echo "  autoloader             Generate shell autocompletion script"
  echo "  help <cmd>             Show detailed help for a command"
  echo ""
  echo "Common Options:"
  echo "  --servers-file=<path>  Specify servers file (default: $DEFAULT_SERVERS_FILE)"
  echo "  --groups-file=<path>   Specify groups file (default: $DEFAULT_GROUPS_FILE)"
  echo "  -v, --verbose          Show detailed output (used with 'info group')"
  echo "  --background, --bg     Run server/group in background (used with 'run')"
  # Options specific to 'add' (--project, --user, --overwrite) are described in 'help add'"
  echo ""
  echo "Note: The tool supports both JSON and YAML formats for configuration files"
  echo ""
  echo "Run '$0 help <command>' for more details on a specific command."
  exit 1
}

# Interactive server selection menu
interactive_menu() {
  local servers=()
  local groups=()
  local custom_groups=()
  local i=1
  local j=1
  local k=1
  local selected_servers=()

  # Build arrays of servers and groups
  while read -r server; do
    servers+=("$i" "$server")
    ((i++))
  done < <(echo "$ALL_SERVERS" | sort)

  while read -r group; do
    groups+=("$j" "$group")
    ((j++))
  done < <(echo "$ALL_GROUPS" | sort)

  # Check for custom groups
  if [ -d "$SCRIPT_DIR/custom_groups" ]; then
    while read -r custom_group; do
      if [ -n "$custom_group" ]; then
        custom_group_name=$(basename "$custom_group" .json)
        custom_groups+=("$k" "$custom_group_name")
        ((k++))
      fi
    done < <(find "$SCRIPT_DIR/custom_groups" -name "*.json" -type f | sort)
  fi

  # Check if we have dialog installed
  if ! command -v dialog &> /dev/null; then
    echo "dialog command not found. Installing dialog..."
    if command -v apt-get &> /dev/null; then
      sudo apt-get update && sudo apt-get install -y dialog
    elif command -v brew &> /dev/null; then
      brew install dialog
    else
      echo "Error: Cannot install dialog. Please install it manually."
      exit 1
    fi
  fi

  # Create temporary files for dialog output
  temp_file=$(mktemp)
  trap 'rm -f $temp_file' EXIT

  # Main menu
  while true; do
    dialog --clear --title "MCP Tool v$VERSION" \
           --menu "Choose an option:" 18 60 12 \
           1 "Run a server" \
           2 "Get server info" \
           3 "Run a server group" \
           4 "Get group info" \
           5 "Setup server environment" \
           6 "View documentation" \
           7 "Add to Claude/Cursor" \
           8 "Create custom group" \
           9 "Run custom group" \
           10 "Run server in separate window" \
           11 "Run group in separate windows" \
           12 "Exit" 2> "$temp_file"

    main_choice=$(cat "$temp_file")

    # Handle menu exit
    if [ -z "$main_choice" ]; then
      clear
      echo "Exiting MCP Tool."
      exit 0
    fi

    case $main_choice in
      1) # Run a server
        dialog --clear --title "Run Server" \
               --menu "Select a server to run:" 20 60 12 \
               "${servers[@]}" 2> "$temp_file"

        server_index=$(cat "$temp_file")
        if [ -n "$server_index" ]; then
          server_name=${servers[$(( server_index * 2 - 1 ))]}
          clear
          "$0" run "$server_name"
        fi
        ;;

      2) # Get server info
        dialog --clear --title "Server Info" \
               --menu "Select a server:" 20 60 12 \
               "${servers[@]}" 2> "$temp_file"

        server_index=$(cat "$temp_file")
        if [ -n "$server_index" ]; then
          server_name=${servers[$(( server_index * 2 - 1 ))]}
          clear
          "$0" info "$server_name"
          read -p "Press Enter to continue..."
        fi
        ;;

      3) # Run a server group
        dialog --clear --title "Run Group" \
               --menu "Select a group to run:" 20 60 12 \
               "${groups[@]}" 2> "$temp_file"

        group_index=$(cat "$temp_file")
        if [ -n "$group_index" ]; then
          group_name=${groups[$(( group_index * 2 - 1 ))]}
          clear
          "$0" run "$group_name"
        fi
        ;;

      4) # Get group info
        dialog --clear --title "Group Info" \
               --menu "Select a group:" 20 60 12 \
               "${groups[@]}" 2> "$temp_file"

        group_index=$(cat "$temp_file")
        if [ -n "$group_index" ]; then
          group_name=${groups[$(( group_index * 2 - 1 ))]}
          clear
          "$0" info "$group_name" --verbose
          read -p "Press Enter to continue..."
        fi
        ;;

      5) # Setup server environment
        dialog --clear --title "Setup Server" \
               --menu "Select a server to configure:" 20 60 12 \
               "${servers[@]}" 2> "$temp_file"

        server_index=$(cat "$temp_file")
        if [ -n "$server_index" ]; then
          server_name=${servers[$(( server_index * 2 - 1 ))]}
          clear
          setup_wizard "$server_name" "$JSON_FILE"
          read -p "Press Enter to continue..."
        fi
        ;;

      6) # View documentation
        clear
        generate_documentation "$JSON_FILE" | less -R
        ;;

      7) # Add to Claude/Cursor
        dialog --clear --title "Integration Options" \
               --menu "Choose integration target:" 15 60 4 \
               1 "Add to Claude (project scope)" \
               2 "Add to Claude (global scope)" \
               3 "Add to Cursor (project scope)" \
               4 "Add to Cursor (global scope)" 2> "$temp_file"

        integration_choice=$(cat "$temp_file")
        if [ -n "$integration_choice" ]; then
          # Choose between server or group
          dialog --clear --title "Select Type" \
                 --menu "Add server or group?" 15 60 3 \
                 1 "Server" \
                 2 "Group" 2> "$temp_file"

          type_choice=$(cat "$temp_file")
          if [ -n "$type_choice" ]; then
            if [ "$type_choice" = "1" ]; then
              # Select a server
              dialog --clear --title "Select Server" \
                     --menu "Choose a server to add:" 20 60 12 \
                     "${servers[@]}" 2> "$temp_file"

              server_index=$(cat "$temp_file")
              if [ -n "$server_index" ]; then
                target_name=${servers[$(( server_index * 2 - 1 ))]}
                clear
                case $integration_choice in
                  1) "$0" claude "$target_name" --project ;;
                  2) "$0" claude "$target_name" --global ;;
                  3) "$0" cursor "$target_name" --project ;;
                  4) "$0" cursor "$target_name" --global ;;
                esac
                read -p "Press Enter to continue..."
              fi
            else
              # Select a group
              dialog --clear --title "Select Group" \
                     --menu "Choose a group to add:" 20 60 12 \
                     "${groups[@]}" 2> "$temp_file"

              group_index=$(cat "$temp_file")
              if [ -n "$group_index" ]; then
                target_name=${groups[$(( group_index * 2 - 1 ))]}
                clear
                case $integration_choice in
                  1) "$0" claude "$target_name" --project ;;
                  2) "$0" claude "$target_name" --global ;;
                  3) "$0" cursor "$target_name" --project ;;
                  4) "$0" cursor "$target_name" --global ;;
                esac
                read -p "Press Enter to continue..."
              fi
            fi
          fi
        fi
        ;;

      8) # Create custom group
        # First, show a dialog to enter the group name
        dialog --clear --title "Create Custom Group" \
               --inputbox "Enter a name for the custom group:" 8 60 2> "$temp_file"

        group_name=$(cat "$temp_file")
        if [ -z "$group_name" ]; then
          continue
        fi

        # Now select servers to include in the group
        selected_servers=()
        while true; do
          dialog --clear --title "Add Servers to Group: $group_name" \
                 --menu "Select a server to add (or Done to finish):" 20 60 13 \
                 0 "Done - Create Group" \
                 "${servers[@]}" 2> "$temp_file"

          server_index=$(cat "$temp_file")
          if [ -z "$server_index" ] || [ "$server_index" = "0" ]; then
            break
          fi

          server_name=${servers[$(( server_index * 2 - 1 ))]}
          # Check if server is already selected
          if ! printf '%s\n' "${selected_servers[@]}" | grep -q "^$server_name$"; then
            selected_servers+=("$server_name")
          fi

          # Show current selection
          dialog --clear --title "Current Selection" \
                 --msgbox "Servers in group '$group_name':\n$(printf '  - %s\n' "${selected_servers[@]}")" 15 60
        done

        # Create the custom group if servers were selected
        if [ ${#selected_servers[@]} -gt 0 ]; then
          clear
          # Convert selected servers to JSON array format
          server_json="["
          for i in "${!selected_servers[@]}"; do
            server_json+="\"${selected_servers[$i]}\""
            if [ $i -lt $((${#selected_servers[@]} - 1)) ]; then
              server_json+=","
            fi
          done
          server_json+="]"

          create_custom_group "$group_name" "$server_json"
          read -p "Press Enter to continue..."
        else
          dialog --clear --title "Error" \
                 --msgbox "No servers selected. Group not created." 8 60
        fi
        ;;

      9) # Run custom group
        # Check if we have any custom groups
        if [ ${#custom_groups[@]} -eq 0 ]; then
          dialog --clear --title "No Custom Groups" \
                 --msgbox "No custom groups found. Create one first." 8 60
          continue
        fi

        dialog --clear --title "Run Custom Group" \
               --menu "Select a custom group to run:" 20 60 12 \
               "${custom_groups[@]}" 2> "$temp_file"

        group_index=$(cat "$temp_file")
        if [ -n "$group_index" ]; then
          group_name=${custom_groups[$(( group_index * 2 - 1 ))]}
          clear

          # Load servers from custom group file
          custom_group_file="$SCRIPT_DIR/custom_groups/${group_name}.json"
          if [ -f "$custom_group_file" ]; then
            custom_server_list=$(jq -r '.servers[]' "$custom_group_file")
            echo "Running custom group: $group_name"
            echo "Servers: $custom_server_list"
            echo "Starting each server in a separate terminal window..."
            run_in_separate_terminals "$custom_server_list"
            read -p "Press Enter to continue..."
          else
            echo "Error: Custom group file not found: $custom_group_file"
            read -p "Press Enter to continue..."
          fi
        fi
        ;;

      10) # Run server in separate window
        dialog --clear --title "Run Server in Separate Window" \
               --menu "Select a server to run:" 20 60 12 \
               "${servers[@]}" 2> "$temp_file"

        server_index=$(cat "$temp_file")
        if [ -n "$server_index" ]; then
          server_name=${servers[$(( server_index * 2 - 1 ))]}
          clear
          echo "Running server in separate window: $server_name"
          run_in_separate_terminals "$server_name"
          read -p "Press Enter to continue..."
        fi
        ;;

      11) # Run group in separate windows
        dialog --clear --title "Run Group in Separate Windows" \
               --menu "Select a group:" 20 60 12 \
               "${groups[@]}" 2> "$temp_file"

        group_index=$(cat "$temp_file")
        if [ -n "$group_index" ]; then
          group_name=${groups[$(( group_index * 2 - 1 ))]}
          clear
          echo "Running group in separate windows: $group_name"
          server_list=$(jq -r --arg group "$group_name" '.groups[$group][]' "$JSON_FILE")
          run_in_separate_terminals "$server_list"
          read -p "Press Enter to continue..."
        fi
        ;;

      12|"") # Exit
        clear
        echo "Exiting MCP Tool."
        exit 0
        ;;
    esac
  done
}