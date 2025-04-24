# MCP Tool Documentation

## Overview

The MCP Tool is a command-line utility for managing Model Context Protocol (MCP) servers. It provides a unified interface for running, configuring, and integrating various MCP servers with tools like Claude and Cursor.

## Key Features

### Core Functionality

- List available MCP servers and server groups
- Run MCP servers individually or as groups
- Display detailed information about servers
- Generate comprehensive documentation for all servers
- Output server definitions in JSON format

### Advanced Features

- **Claude Integration**: Easily add server definitions to Claude MCP
- **Cursor Integration**: Add server definitions to Cursor MCP config
- **Autoloader for .zshrc**: Integrate with your shell environment with autocomplete
- **Interactive Mode**: Select and manage servers through a user-friendly menu
- **Configuration Wizard**: Set up environment variables required by servers
- **Improved Error Handling**: Better feedback when issues occur
- **Enhanced Help System**: Detailed usage information for each command

## Installation

1. Clone or download the script files to your preferred location:
   ```bash
   git clone https://github.com/your-username/mcptool.git
   cd mcptool
   ```

2. Make the main script executable:
   ```bash
   chmod +x mcptool.sh
   ```

3. Ensure you have the required dependencies:
   - `jq`: JSON processor (required for parsing server configurations)
   - `dialog`: Optional, used for interactive mode

4. (Optional) Create an alias for easier access:
   ```bash
   alias mcpt='/path/to/mcptool.sh'
   ```

## Usage

The main script (`mcptool.sh`) serves as the unified command center for all functionality.

### Basic Commands

```bash
MCP Tool v1.2.0 - Manage MCP Servers

Usage: ./bin/mcptool.sh <command> [target] [options]

Commands:
  list                   List servers and groups
  run <target> [--bg]    Run a server or group. Groups run in separate terminals.
                         Use --background or --bg to run in detached background mode.
  add <server> <opts>    Add server definition to a required backend/file.
                         Target Options (required): --claude | --cursor [--global] | --json <file> | <file>
  info <target> [-v]     Show info for a server or group (use -v for group details)
  json <target>          Output server/group JSON definition
  docs                   Show documentation for all servers
  interactive            Launch interactive TUI menu (requires 'dialog')
  autoloader             Generate shell autocompletion script
  help <cmd>             Show detailed help for a command

Common Options:
  --servers-file=<path>  Specify servers file (default: /Users/estiens/code/mcptool/config/servers.json)
  --groups-file=<path>   Specify groups file (default: /Users/estiens/code/mcptool/config/groups.json)
  -v, --verbose          Show detailed output (used with 'info group')
  --background, --bg     Run server/group in background (used with 'run')

Note: The tool supports both JSON and YAML formats for configuration files

Run './bin/mcptool.sh help <command>' for more details on a specific command.
```

### Common Options

- `-v, --verbose`: Show detailed output (especially useful with `info` command)
- `--project`: Use project-level scope for Claude/Cursor integration (default)
- `--global`: Use global/user-level scope for Claude/Cursor integration
- `--json-file=<path>`: Specify custom JSON file location

### Environment Variables

- `MCP_CONFIG_FILE`: Alternative path to the JSON configuration file

## Shell Integration with Autoloader

The autoloader feature creates a script that can be sourced in your `.zshrc` file to provide convenient shell functions and tab completion for MCP server commands.

1. Generate the autoloader file:
   ```bash
   ./mcptool.sh autoloader
   ```

2. Add the following line to your `.zshrc` file:
   ```bash
   source ~/.mcp_autoloader.zsh
   ```

3. After reloading your shell, you can use these commands with tab completion:
   - `mcpt list`: List all available servers and groups
   - `mcpt run <server|group>`: Run a specific server or group
   - `mcpt info <server|group>`: Get information about a server or group
   - `mcpt json <server|group>`: Get JSON definition for a server or group
   - `mcpt add <server> --claude|--cursor [--global]|--json <file>|<file>`: Add server definition
   - `mcpt docs`: Generate comprehensive documentation
   - `mcpt interactive`: Launch interactive mode

## Interactive Mode

The interactive mode provides a user-friendly menu interface for managing MCP servers. Launch it with:

```bash
./mcptool.sh interactive
```

The menu allows you to:
- Run a server
- Get server information
- Run a server group
- Get group information
- View documentation
- Add server definitions using the 'add' command (outside interactive mode)
- Exit the application

## Claude and Cursor Integration

MCP Tool makes it easy to add server definitions to both Claude and Cursor MCP:

### Claude Integration

```bash
# Add a server definition to Claude MCP (project scope)
./mcptool.sh add server_name --claude

# Add a server definition to Claude MCP (global/user scope)
./mcptool.sh add server_name --claude --global

# Add a server definition, overwriting existing Claude config
./mcptool.sh add server_name --claude --overwrite

# Note: Adding entire groups directly is not supported via 'add'. Add servers individually.
```

### Cursor Integration

```bash
# Add a server definition to Cursor MCP (project scope - ./.cursor/mcp.json)
./mcptool.sh add server_name --cursor

# Add a server definition to Cursor MCP (global scope - ~/.cursor/mcp.json)
./mcptool.sh add server_name --cursor --global

# Add a server definition, overwriting existing Cursor config
./mcptool.sh add server_name --cursor --overwrite

# Note: Adding entire groups directly is not supported via 'add'. Add servers individually.
```

### Adding to JSON/YAML Files

```bash
# Add a server definition to a specific JSON file
./mcptool.sh add server_name --json path/to/your/config.json

# Add a server definition, overwriting the target JSON file
./mcptool.sh add server_name --json path/to/your/config.json --overwrite

# Add a server definition to a specific YAML file (or any text file)
./mcptool.sh add server_name path/to/your/config.yaml

# Add a server definition, overwriting the target YAML file
./mcptool.sh add server_name path/to/your/config.yaml --overwrite
```

## Configuration Files

The MCP servers are defined in a JSON configuration file with the following structure:

```json
{
  "servers": {
    "server_name": {
      "command": "command_to_run",
      "args": ["arg1", "arg2"],
      "env": {
        "ENV_VAR1": "value1",
        "ENV_VAR2": "value2"
      },
      "required_env": ["ENV_VAR1", "ENV_VAR2"],
      "description": "Server description"
    }
  },
  "groups": {
    "group_name": ["server1", "server2"]
  }
}
```

## Troubleshooting

### Common Issues

1. **JSON file not found**
   - Ensure you're specifying the correct path with `--json-file=path/to/file`
   - Check if the `MCP_CONFIG_FILE` environment variable is set correctly
   - The default location is in the same directory as the script: `mcp_servers.json`

2. **Missing dependencies**
   - Install jq: `brew install jq` (macOS) or `sudo apt-get install -y jq` (Ubuntu/Debian)
   - Install dialog (for interactive mode): `brew install dialog` (macOS) or `sudo apt-get install -y dialog` (Ubuntu/Debian)

3. **Missing environment variables**
   - Some servers require environment variables. Check the server's documentation (via `mcptool docs` or `mcptool info <server>`) for required variables.
   - Set them in your environment or a `.env` file (e.g., `.env.mcp`) and source it (`source .env.mcp`).

4. **'add' command fails**
   - Ensure you provide a valid target: `--claude`, `--cursor [--global]`, `--json <file>`, or a filename `<file>`.
   - For `--claude`: Make sure the Claude CLI is installed and in your PATH.
   - For `--cursor` or file targets: Check if the target directory/file is writable.

5. **Invalid JSON error**
   - Validate your JSON file using `jq empty your_file.json`
   - Common issues include missing commas, extra commas, or improperly quoted strings

### Platform-Specific Issues

- **macOS**: The `sed -i` command works differently on macOS. The script handles this automatically.
- **Linux**: No known platform-specific issues.
- **Windows**: Not directly supported. Consider using WSL (Windows Subsystem for Linux).

## Contributing

To add new MCP servers to the library:

1. Edit the JSON configuration file to add the new server definition
2. Test the server with the MCP Tool
3. Document the server's purpose, requirements, and usage
4. Submit a pull request if you're contributing to the main repository

## License

This tool is provided under the unlicense of DWTFYouWant
