# Elixir Phoenix PostgreSQL Development Template

A Coder workspace template for Elixir Phoenix development with PostgreSQL database.

## What's Included

- **Elixir Environment**: Configurable Elixir version (default: 1.18.4-otp-28)
- **PostgreSQL Database**: Sidecar container with configurable version (default: 17)
- **VS Code Server**: Web-based IDE accessible via browser
- **Phoenix Tools**: Pre-installed Phoenix framework and development tools

## Architecture

- **Workspace Isolation**: Each workspace runs in a separate pod in the `coder-workspaces` namespace
- **Persistent Storage**: 20GB home directory + 10GB PostgreSQL data (configurable: 10-100GB)
- **Network Isolation**: PostgreSQL accessible only within the workspace pod via localhost
- **RBAC**: Each workspace gets its own ServiceAccount with minimal required permissions

## Key Design Decisions

- **Hardcoded namespace**: All workspaces use `coder-workspaces` namespace (managed by Flux GitOps)
- **Standard dev credentials**: PostgreSQL uses `postgres:postgres` for development convenience
- **Sidecar database**: PostgreSQL runs as a sidecar container for zero-config Phoenix development
- **GitOps compliance**: Namespace created via Flux, workspaces managed by Coder

## Usage

1. Create workspace from template
2. Customize CPU (1-4 cores), memory (2-8GB), and disk size (10-100GB)
3. Access VS Code via browser or Phoenix dev server at port 4000
4. Run standard Phoenix commands: `mix phx.new my_app`, `mix ecto.create`