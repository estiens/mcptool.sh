#!/usr/bin/env bash

# Common functions for MCP Server Helper Tool

# Check for missing required environment variables (non-interactive)
# Usage: ensure_env_vars_set <server_name> <servers_file>
# Prints missing env vars (one per line) if any, returns 0 if all set, 1 if missing
ensure_env_vars_set() {
  local server_name="$1"
  local servers_file="$2"
  local server_json
  server_json=$(get_server_definition "$server_name" "$servers_file")
  if [ -z "$server_json" ] || [ "$server_json" = "null" ]; then
    echo "Error: Server '$server_name' not found in config." >&2
    return 2
  fi
  local required_envs=()
  required_envs=()
  while IFS= read -r line; do
    required_envs+=("$line")
  done < <(echo "$server_json" | jq -r '.required_env[]?' 2>/dev/null || echo "")
  local missing_envs=()
  for envvar in "${required_envs[@]}"; do
    [ -z "$envvar" ] && continue
    if [ -z "${!envvar}" ]; then
      missing_envs+=("$envvar")
    fi
  done
  if [ ${#missing_envs[@]} -gt 0 ]; then
    echo "Required environment variable(s) not set for $server_name:" >&2
    printf "  - %s\n" "${missing_envs[@]}" >&2

    # Create or ensure .env.mcp exists with proper permissions
    local env_file=".env.mcp"
    if [ ! -f "$env_file" ]; then
      touch "$env_file"
      chmod 600 "$env_file" # More secure permissions for potentially sensitive data
    fi

    # Ask if user wants to enter the variables now
    local setup_now
    read -p "Would you like to enter these values now? (y/n) [y]: " setup_now
    setup_now=${setup_now:-y}

    if [[ "$setup_now" == "y" || "$setup_now" == "Y" ]]; then
      local missing_vars_remain=0
      for env_var in "${missing_envs[@]}"; do
        # Prompt for value
        local new_value
        read -p "Enter value for $env_var: " new_value

        if [ -n "$new_value" ]; then
          # Escape any double quotes in the new value
          new_value=${new_value//\"/\\\"}

          # Create a temporary file with proper permissions
          local temp_file
          temp_file=$(mktemp)
          chmod 600 "$temp_file"

          if grep -q "^$env_var=" "$env_file" 2>/dev/null; then
            # Use awk for reliable replacement
            awk -v var="$env_var" -v val="$new_value" '
              BEGIN { FS=OFS="=" }
              $1 == var { $2 = "\"" val "\"" }
              { print }
            ' "$env_file" > "$temp_file" && mv "$temp_file" "$env_file"
          else
            # Append if not found
            echo "$env_var=\"$new_value\"" >> "$env_file"
            rm -f "$temp_file" # Clean up temp file if not used
          fi

          # Export the variable for the current session
          export "$env_var=$new_value"
          echo "Updated $env_var in $env_file and current environment"
        else
          # If user didn't provide a value, count it as still missing
          ((missing_vars_remain++))
          echo "No value provided for $env_var" >&2
        fi
      done

      echo "Environment variables saved to $env_file"
      echo "For future sessions, run 'source $env_file' to load these variables"

      # If any required vars still missing, return failure
      if [ $missing_vars_remain -gt 0 ]; then
        echo "Some required environment variables are still missing." >&2
        return 1 # Signal failure (skip)
      fi
      # All provided, return success
      return 0
    else
      # User chose not to enter values
      echo "Skipping operation for $server_name due to missing environment variables." >&2
      return 1 # Signal failure (skip)
    fi
  else
    # No missing env vars found initially
    return 0
  fi
}

# Validate server definition existence and required fields
# Usage: get_validated_server_definition <server_name> <servers_file>
# Prints server JSON if valid, error and returns 1 if not
get_validated_server_definition() {
  local server_name="$1"
  local servers_file="$2"
  local server_json
  server_json=$(get_server_definition "$server_name" "$servers_file")
  if [ -z "$server_json" ] || [ "$server_json" = "null" ]; then
    echo "Error: Server '$server_name' not found in config." >&2
    return 1
  fi
  local server_cmd
  server_cmd=$(echo "$server_json" | jq -r '.command')
  if [ -z "$server_cmd" ] || [ "$server_cmd" = "null" ]; then
    echo "Error: No command defined for server '$server_name'" >&2
    return 1
  fi
  echo "$server_json"
  return 0
}

# Process environment variables with proper error handling
# Returns an array of env var assignments suitable for use with env command
process_env_vars() {
  local server="$1"
  local json_file="$2"
  local env_array=()
  local env_vars
  
  # Use a safer way to handle potential errors from jq
  env_vars=()
  while IFS= read -r line; do
    env_vars+=("$line")
  done < <(jq -r --arg server "$server" '.servers[$server].env | keys[]?' "$json_file" 2>/dev/null || echo "")
  
  if [ ${#env_vars[@]} -gt 0 ]; then
    for var in "${env_vars[@]}"; do
      # Skip empty entries
      [ -z "$var" ] && continue
      
      # Get the template value from JSON
      template_value=$(jq -r --arg server "$server" --arg var "$var" '.servers[$server].env[$var]' "$json_file")
      
      # Safely evaluate any ${VAR} references in the value
      # Using printf to avoid issues with special characters
      evaluated_value=$(eval printf '%s' "$template_value" 2>/dev/null || echo "$template_value")
      
      # Add to the env array with proper quoting
      env_array+=("$var=$evaluated_value")
    done
  fi
  
  # Build environment string output with proper quoting
  local env_string=""
  for env_pair in "${env_array[@]}"; do
    # Extract key and value
    local key="${env_pair%%=*}"
    local value="${env_pair#*=}"
    # Add to env string with proper shell escaping
    env_string="${env_string}${key}=$(printf '%q' "$value") "
  done
  
  echo "$env_string"
}

# Generator functions moved to lib/mcplib_generators.sh

# Read servers from server json file
get_servers() {
  local servers_file="$1"
  local servers_yaml="${servers_file%.json}.yaml"
  local servers_yml="${servers_file%.json}.yml"
  
  # Try JSON format first
  if [ -f "$servers_file" ]; then
    jq -r 'keys[]' "$servers_file" 2>/dev/null | sort
  # Try YAML format if JSON doesn't exist
  elif [ -f "$servers_yaml" ] || [ -f "$servers_yml" ]; then
    # Check if yq is installed
    if ! command -v yq &> /dev/null; then
      echo "Error: YAML file detected (${servers_yaml} or ${servers_yml}) but 'yq' command not found." >&2
      echo "Please install yq to use YAML format configuration files." >&2
      exit 1
    fi
    
    if [ -f "$servers_yaml" ]; then
      yq -r 'keys[]' "$servers_yaml" 2>/dev/null | sort
    elif [ -f "$servers_yml" ]; then
      yq -r 'keys[]' "$servers_yml" 2>/dev/null | sort
    fi
  else
    echo ""
  fi
}

# Read groups from groups json file
get_groups() {
  local groups_file="$1"
  local groups_yaml="${groups_file%.json}.yaml"
  local groups_yml="${groups_file%.json}.yml"
  
  # Try JSON format first
  if [ -f "$groups_file" ]; then
    jq -r '.[].name' "$groups_file" 2>/dev/null | sort
  # Try YAML format if JSON doesn't exist
  elif [ -f "$groups_yaml" ] || [ -f "$groups_yml" ]; then
    # Check if yq is installed
    if ! command -v yq &> /dev/null; then
      echo "Error: YAML file detected (${groups_yaml} or ${groups_yml}) but 'yq' command not found." >&2
      echo "Please install yq to use YAML format configuration files." >&2
      exit 1
    fi
    
    if [ -f "$groups_yaml" ]; then
      yq -r '.[].name' "$groups_yaml" 2>/dev/null | sort
    elif [ -f "$groups_yml" ]; then
      yq -r '.[].name' "$groups_yml" 2>/dev/null | sort
    fi
  else
    echo ""
  fi
}

# Get servers in a group
get_group_servers() {
  local group_name="$1"
  local groups_file="$2"
  local groups_yaml="${groups_file%.json}.yaml"
  local groups_yml="${groups_file%.json}.yml"
  
  # Try JSON format first
  if [ -f "$groups_file" ]; then
    jq -r --arg group "$group_name" '.[] | select(.name == $group) | .servers[]' "$groups_file" 2>/dev/null
  # Try YAML format if JSON doesn't exist
  elif [ -f "$groups_yaml" ] || [ -f "$groups_yml" ]; then
    # Check if yq is installed
    if ! command -v yq &> /dev/null; then
      echo "Error: YAML file detected (${groups_yaml} or ${groups_yml}) but 'yq' command not found." >&2
      echo "Please install yq to use YAML format configuration files." >&2
      exit 1
    fi
    
    if [ -f "$groups_yaml" ]; then
      yq -r --arg group "$group_name" '.[] | select(.name == $group) | .servers[]' "$groups_yaml" 2>/dev/null
    elif [ -f "$groups_yml" ]; then
      yq -r --arg group "$group_name" '.[] | select(.name == $group) | .servers[]' "$groups_yml" 2>/dev/null
    fi
  else
    echo ""
  fi
}

# Get server definition from servers.json
get_server_definition() {
  local server_name="$1"
  local servers_file="$2"
  local servers_yaml="${servers_file%.json}.yaml"
  local servers_yml="${servers_file%.json}.yml"
  
  # Try JSON format first
  if [ -f "$servers_file" ]; then
    jq -r --arg server "$server_name" '.[$server]' "$servers_file" 2>/dev/null
  # Try YAML format if JSON doesn't exist
  elif [ -f "$servers_yaml" ] || [ -f "$servers_yml" ]; then
    # Check if yq is installed
    if ! command -v yq &> /dev/null; then
      echo "Error: YAML file detected (${servers_yaml} or ${servers_yml}) but 'yq' command not found." >&2
      echo "Please install yq to use YAML format configuration files." >&2
      exit 1
    fi
    
    if [ -f "$servers_yaml" ]; then
      yq -r --arg server "$server_name" '.[$server]' "$servers_yaml" 2>/dev/null
    elif [ -f "$servers_yml" ]; then
      yq -r --arg server "$server_name" '.[$server]' "$servers_yml" 2>/dev/null
    fi
  else
    echo ""
  fi
}


# Setup wizard for configuring environment variables
setup_wizard() {
  local server="$1"
  local file="$2"
  local required_envs=()
  
  # Get server definition
  SERVER_DEF=$(get_server_definition "$server" "$file")
  
  # Safely get required environment variables as an array
  required_envs=()
  while IFS= read -r line; do
    required_envs+=("$line")
  done < <(echo "$SERVER_DEF" | jq -r '.required_env[]?' 2>/dev/null || echo "")
  
  if [ ${#required_envs[@]} -eq 0 ] || [ -z "${required_envs[0]}" ]; then
    echo "Server '$server' does not require any environment variables."
    return 0
  fi
  
  echo "Setup wizard for '$server'"
  echo "This will help you configure the required environment variables."
  echo ""
  
  # Create or update .env file
  local env_file=".env.mcp"
  
  # Create file if it doesn't exist with proper permissions
  if [ ! -f "$env_file" ]; then
    touch "$env_file"
    chmod 600 "$env_file"  # More secure permissions for potentially sensitive data
  fi
  
  for env_var in "${required_envs[@]}"; do
    # Skip empty entries
    [ -z "$env_var" ] && continue
    
    # Check if variable is already set in environment
    if [ -n "${!env_var-}" ]; then
      current_value="${!env_var}"
      echo "Environment variable $env_var is already set to: $current_value"
      read -p "Do you want to update it? (y/n) [n]: " update_var
      if [ "$update_var" != "y" ]; then
        continue
      fi
    else
      # Check if variable is in .env file - use grep with word boundary to avoid partial matches
      current_value=$(grep "^$env_var=" "$env_file" 2>/dev/null | cut -d= -f2- | sed 's/^"//;s/"$//' || echo "")
      if [ -n "$current_value" ]; then
        echo "Environment variable $env_var is set in $env_file to: $current_value"
        read -p "Do you want to update it? (y/n) [n]: " update_var
        if [ "$update_var" != "y" ]; then
          continue
        fi
      fi
    fi
    
    # Prompt for new value
    read -p "Enter value for $env_var: " new_value
    
    # Escape any double quotes in the new value
    new_value=${new_value//\"/\\\"}
    
    # Create a temporary file with proper permissions
    temp_file=$(mktemp)
    chmod 600 "$temp_file"
    
    if grep -q "^$env_var=" "$env_file" 2>/dev/null; then
      # Use awk for more reliable replacement that works across platforms
      awk -v var="$env_var" -v val="$new_value" '
        $0 ~ "^"var"=" { print var"=\""val"\""; next }
        { print }
      ' "$env_file" > "$temp_file"
      
      mv "$temp_file" "$env_file"
    else
      echo "$env_var=\"$new_value\"" >> "$env_file"
      rm "$temp_file"
    fi
    
    echo "Updated $env_var in $env_file"
  done
  
  echo ""
  echo "Setup complete for '$server'."
  echo "To use these environment variables, run:"
  echo "source $env_file"
  echo ""
  echo "You may want to add this line to your shell configuration file to automatically load these variables."
}

# Check for required dependencies
check_dependencies() {
  local interactive_mode="${1:-false}"
  local missing_deps=0
  local missing_tools=()
  
  # Required tools for all modes
  local required_tools=(jq sed awk)
  
  # Check each required tool
  for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
      missing_tools+=("$tool")
      missing_deps=1
    fi
  done
  
  # We no longer need to warn about yq here as we'll check when we try to read YAML files
  
  # Report missing tools
  if [ ${#missing_tools[@]} -gt 0 ]; then
    echo "Error: The following required tools are not installed:"
    for tool in "${missing_tools[@]}"; do
      echo "  - $tool"
    done
    
    echo ""
    echo "Install the missing tools with:"
    echo "  - macOS: brew install ${missing_tools[*]}"
    echo "  - Ubuntu/Debian: sudo apt-get install -y ${missing_tools[*]}"
    echo "  - Fedora: sudo dnf install -y ${missing_tools[*]}"
  fi
  
  # Check for dialog if running or checking interactive mode
  if [ "$interactive_mode" = "interactive" ] && ! command -v dialog &> /dev/null; then
    echo "Warning: dialog is not installed. Interactive mode requires dialog."
    echo "The tool will attempt to install dialog when interactive mode is used."
    # Not incrementing missing_deps as this is just a warning, not an error
  fi
  
  # Check for environment
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # On macOS, ensure the gnubin version of sed is preferred if installed (from brew)
    if command -v gsed &> /dev/null; then
      echo "Note: GNU sed (gsed) detected on macOS. This tool will use built-in cross-platform handling."
    fi
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # On Linux, no additional checks needed
    :
  else
    echo "Warning: Unsupported operating system: $OSTYPE"
    echo "The tool may not function correctly on this platform."
  fi
  
  # Return non-zero if any required dependencies are missing
  return $missing_deps
}

# Validate JSON server definition
validate_server() {
  local server="$1"
  local json_file="$2"
  local strict="${3:-false}"
  local errors=0
  local warnings=0
  
  # Check if server exists in JSON
  if ! jq -e --arg server "$server" '.servers[$server]' "$json_file" >/dev/null 2>&1; then
    echo "Error: Server '$server' not found in $json_file"
    return 1
  fi
  
  # Check for required fields
  if ! jq -e --arg server "$server" '.servers[$server].command' "$json_file" >/dev/null 2>&1; then
    echo "Error: Server '$server' is missing required 'command' field"
    ((errors++))
  fi
  
  # Validate args is an array if present
  if jq -e --arg server "$server" '.servers[$server] | has("args")' "$json_file" >/dev/null 2>&1; then
    if ! jq -e --arg server "$server" '.servers[$server].args | type == "array"' "$json_file" >/dev/null 2>&1; then
      echo "Error: Server '$server' has 'args' field but it's not an array"
      ((errors++))
    fi
  else
    echo "Warning: Server '$server' doesn't have an 'args' field (may be intentional)"
    ((warnings++))
  fi
  
  # Validate env is an object if present
  if jq -e --arg server "$server" '.servers[$server] | has("env")' "$json_file" >/dev/null 2>&1; then
    if ! jq -e --arg server "$server" '.servers[$server].env | type == "object"' "$json_file" >/dev/null 2>&1; then
      echo "Error: Server '$server' has 'env' field but it's not an object"
      ((errors++))
    fi
  fi
  
  # Validate required_env is an array if present
  if jq -e --arg server "$server" '.servers[$server] | has("required_env")' "$json_file" >/dev/null 2>&1; then
    if ! jq -e --arg server "$server" '.servers[$server].required_env | type == "array"' "$json_file" >/dev/null 2>&1; then
      echo "Error: Server '$server' has 'required_env' field but it's not an array"
      ((errors++))
    fi
    
    # Check if required_env variables are specified in env
    if jq -e --arg server "$server" '.servers[$server] | has("env")' "$json_file" >/dev/null 2>&1; then
      local required_envs
      required_envs=()
      while IFS= read -r line; do
        required_envs+=("$line")
      done < <(jq -r --arg server "$server" '.servers[$server].required_env[]?' "$json_file")
      
      for env_var in "${required_envs[@]}"; do
        [ -z "$env_var" ] && continue
        
        # Check if this required env var has a template in env
        if ! jq -e --arg server "$server" --arg env "$env_var" '.servers[$server].env | has($env)' "$json_file" >/dev/null 2>&1; then
          echo "Warning: Server '$server' requires env var '$env_var' but doesn't provide a template in env object"
          ((warnings++))
        fi
      done
    fi
  fi
  
  # Validate description is present (helpful for users)
  if ! jq -e --arg server "$server" '.servers[$server] | has("description")' "$json_file" >/dev/null 2>&1; then
    echo "Warning: Server '$server' doesn't have a 'description' field"
    ((warnings++))
  fi
  
  # Show summary
  if [ $errors -gt 0 ]; then
    echo "Validation found $errors error(s) and $warnings warning(s) for server '$server'"
    return 1
  elif [ $warnings -gt 0 ] && [ "$strict" = "true" ]; then
    echo "Validation found $warnings warning(s) for server '$server' (strict mode enabled)"
    return 1
  elif [ $warnings -gt 0 ]; then
    echo "Validation found $warnings warning(s) for server '$server' (passed with warnings)"
    return 0
  else
    # If no output is desired for success, uncomment the next line
    # echo "Server '$server' passed validation"
    return 0
  fi
}

# Function to validate the entire config file
validate_config() {
  local json_file="$1"
  local strict="${2:-false}"
  local errors=0
  local warnings=0
  
  # Check if file exists
  if [ ! -f "$json_file" ]; then
    echo "Error: JSON file not found: $json_file"
    return 1
  fi
  
  # Validate basic JSON structure
  if ! jq empty "$json_file" 2>/dev/null; then
    echo "Error: Invalid JSON in $json_file"
    return 1
  fi
  
  # Check for servers and groups sections
  if ! jq -e '.servers' "$json_file" >/dev/null 2>&1; then
    echo "Error: Missing 'servers' section in $json_file"
    return 1
  fi
  
  # Warn if groups section is missing (only in strict mode)
  if ! jq -e '.groups' "$json_file" >/dev/null 2>&1; then
    if [ "$strict" = "true" ]; then
        echo "Warning: Missing 'groups' section in $json_file"
        ((warnings++))
    fi
  fi
  
  # Validate all servers
  echo "Validating servers..."
  local server_count=0
  while read -r server; do
    # Skip if empty
    [ -z "$server" ] && continue
    
    echo -n "  - $server: "
    if validate_server "$server" "$json_file" "$strict" >/dev/null; then
      echo "OK"
    else
      validate_server "$server" "$json_file" "$strict" | sed 's/^/    /'
      ((errors++))
    fi
    ((server_count++))
  done < <(jq -r '.servers | keys[]?' "$json_file")
  
  # Validate all groups reference valid servers
  if jq -e '.groups' "$json_file" >/dev/null 2>&1; then
    echo "Validating groups..."
    local group_count=0
    while read -r group; do
      # Skip if empty
      [ -z "$group" ] && continue
      
      echo -n "  - $group: "
      local invalid_servers=()
      
      # Check each server in the group
      while read -r group_server; do
        # Skip if empty
        [ -z "$group_server" ] && continue
        
        if ! jq -e --arg server "$group_server" '.servers[$server]' "$json_file" >/dev/null 2>&1; then
          invalid_servers+=("$group_server")
        fi
      done < <(jq -r --arg group "$group" '.groups[$group][]?' "$json_file")
      
      if [ ${#invalid_servers[@]} -eq 0 ]; then
        echo "OK"
      else
        echo "WARN - References invalid servers:"
        for invalid in "${invalid_servers[@]}"; do
          echo "    - $invalid"
        done
        ((warnings++))
      fi
      ((group_count++))
    done < <(jq -r '.groups | keys[]?' "$json_file")
  fi
  
  # Summary removed as per user request
  # echo ""
  # echo "Validation complete:"
  # echo "  - Servers: $server_count"
  # echo "  - Groups: $group_count"
  # echo "  - Errors: $errors"
  # echo "  - Warnings: $warnings"
  
  if [ $errors -gt 0 ]; then
    return 1
  elif [ $warnings -gt 0 ] && [ "$strict" = "true" ]; then
    return 1
  else
    return 0
  fi
}