# MCP Tool

A command-line utility for managing Model Context Protocol (MCP) servers, with integration for Claude and Cursor.

## Features

- Run MCP servers individually or as groups
- Detailed information about servers and groups
- Export server configurations in JSON format
- Easy integration with Claude and Cursor
- Interactive mode with dialog-based UI
- Environment variable management
- Comprehensive shell completion for zsh
- Support for both JSON and YAML configuration files

## Directory Structure

```
mcptool/
├── bin/           # Executable scripts
├── lib/           # Library functions
├── config/        # Configuration files
│   ├── servers.json  # Server definitions
│   └── groups.json   # Group definitions
├── README.md      # This file
└── LICENSE        # License information
```

## Quick Start

```bash
# List all available servers and groups
./bin/mcptool.sh list

# Run a specific server
./bin/mcptool.sh run server_name

# Get information about a server
./bin/mcptool.sh info server_name

# Add server to Claude MCP
./bin/mcptool.sh claude server_name

# Add server to Cursor MCP
./bin/mcptool.sh cursor server_name
```

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/your-username/mcptool.git
   cd mcptool
   ```

2. Make the script executable:
   ```bash
   chmod +x bin/mcptool.sh
   ```

3. (Optional) Create a symbolic link for easy access:
   ```bash
   sudo ln -s "$(pwd)/bin/mcptool.sh" /usr/local/bin/mcptool
   ```

4. (Optional) Generate the autoloader script for shell integration:
   ```bash
   ./bin/mcptool.sh autoloader
   ```

5. Add to your .zshrc for shell integration:
   ```bash
   source ~/.mcp_autoloader.zsh
   ```

## Configuration

The tool uses two main configuration files:

- `config/servers.json`: Contains the definition of all available MCP servers
- `config/groups.json`: Contains server groupings for easier management

You can also use YAML format (`servers.yaml` and `groups.yaml`) if you have the `yq` tool installed.

## Dependencies

- `jq`: Required for JSON processing
- `yq`: Optional, needed for YAML support
- `dialog`: Optional, used for interactive mode

## Documentation

For full documentation, run:

```bash
./bin/mcptool.sh help
```

## License

MIT