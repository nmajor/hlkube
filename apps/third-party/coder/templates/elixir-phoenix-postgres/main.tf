terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}

data "coder_provisioner" "me" {
}

data "coder_workspace" "me" {
}

# Simplified namespace configuration
locals {
  namespace = "coder-workspaces"
}

# Template parameters
data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU Cores"
  description  = "Number of CPU cores"
  default      = 2
  type         = "number"
  validation {
    min = 1
    max = 4
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "Amount of memory in GB"
  default      = 4
  type         = "number"
  validation {
    min = 2
    max = 8
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Disk Size (GB)"
  description  = "Size of /home/coder for code, deps, DB. 20-30GB recommended for Phoenix development."
  default      = 20
  type         = "number"
  mutable      = false
  validation {
    min = 10
    max = 100
  }
}

data "coder_parameter" "erlang_version" {
  name         = "erlang_version"
  display_name = "Erlang/OTP Version"
  description  = "Erlang/OTP version to install (e.g., 27.3.4, 27.2, 26.2.5). Use format: otp@VERSION"
  default      = "27.3.4"
  type         = "string"
  validation {
    regex = "^\\d+(\\.\\d+)?(\\.\\d+)?(\\.\\d+)?$"
    error = "Please use a valid OTP version format like '27.3.4' or '26.2.5'"
  }
}

data "coder_parameter" "elixir_version" {
  name         = "elixir_version"
  display_name = "Elixir Version"
  description  = "Elixir version to install (e.g., 1.18.4, 1.17.3, 1.16.3). Use format: elixir@VERSION"
  default      = "1.18.4"
  type         = "string"
  validation {
    regex = "^\\d+\\.\\d+\\.\\d+$"
    error = "Please use a valid Elixir version format like '1.18.4' or '1.17.3'"
  }
}

data "coder_parameter" "dotfiles_url" {
  name         = "dotfiles_url"
  display_name = "Dotfiles Repository"
  description  = "Git repository URL for your dotfiles (leave empty to skip). Use SSH format (git@github.com:user/dotfiles.git) for private repos."
  default      = ""
  type         = "string"
  mutable      = true
}

provider "kubernetes" {
  config_path = null
}

# Reference existing namespace
data "kubernetes_namespace" "workspace" {
  metadata {
    name = local.namespace
  }
}

# Reference workspace secrets
data "kubernetes_secret" "workspace_secrets" {
  metadata {
    name      = "workspace-secrets"
    namespace = local.namespace
  }
}


# Coder agent configuration
resource "coder_agent" "main" {
  arch                    = data.coder_provisioner.me.arch
  os                      = "linux"
  startup_script_behavior = "blocking"
  startup_script = <<-EOT
    #!/bin/bash
    set -euo pipefail

    echo "🚀 Setting up Elixir Phoenix development environment..."

    # Install minimal dependencies (no compilation needed!)
    echo "📦 Installing minimal dependencies..."
    sudo apt-get update
    sudo apt-get install -y curl unzip zsh git inotify-tools

    # Download and run official Elixir install script
    echo "💎 Installing Elixir ${data.coder_parameter.elixir_version.value} with OTP ${data.coder_parameter.erlang_version.value}..."
    curl -fsSO https://elixir-lang.org/install.sh
    sh install.sh elixir@${data.coder_parameter.elixir_version.value} otp@${data.coder_parameter.erlang_version.value}

    # Set up PATH using the actual installed directories
    installs_dir=$HOME/.elixir-install/installs

    # Find the actual installed versions (install script may pick different versions)
    otp_actual_dir=$(ls -1 $installs_dir/otp/ | head -1)
    elixir_actual_dir=$(ls -1 $installs_dir/elixir/ | head -1)

    echo "📋 Found installations:"
    echo "  • OTP: $otp_actual_dir"
    echo "  • Elixir: $elixir_actual_dir"

    # Add to bashrc for future sessions using actual directories
    echo "export PATH=\$HOME/.elixir-install/installs/otp/$otp_actual_dir/bin:\$PATH" >> ~/.bashrc
    echo "export PATH=\$HOME/.elixir-install/installs/elixir/$elixir_actual_dir/bin:\$PATH" >> ~/.bashrc

    # Export for current session using actual directories
    export PATH=$installs_dir/otp/$otp_actual_dir/bin:$PATH
    export PATH=$installs_dir/elixir/$elixir_actual_dir/bin:$PATH

    # Verify PATH is working
    echo "🔍 Verifying installation..."
    which elixir && which mix

    # Install Elixir development tools
    echo "🔧 Installing Elixir development tools..."
    mix local.hex --force
    mix local.rebar --force
    mix archive.install hex phx_new --force

    # Install global elixir libs
    mix archive.install hex igniter_new --force
    mix archive.install hex phx_new 1.8.1 --force

    # Create app directory and set as default
    echo "📁 Creating app directory..."
    mkdir -p /home/coder/app

    # Setup zsh with Oh My Zsh and Starship prompt
    echo "🐚 Setting up zsh with Oh My Zsh and Starship prompt..."
    # Install Oh My Zsh (skip if already exists)
    if [ -d "$HOME/.oh-my-zsh" ]; then
        echo "Oh My Zsh is already installed, skipping installation."
    else
        sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi

    # Install Starship prompt
    echo "⭐ Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- --yes

    # Change default shell to zsh
    sudo chsh -s $(which zsh) coder

    # Configure zsh with Elixir paths and Starship
    cat >> ~/.zshrc << 'ZSHEOF'

# Elixir/Erlang paths
export PATH=$HOME/.elixir-install/installs/otp/$(ls -1 $HOME/.elixir-install/installs/otp/ | head -1)/bin:$PATH
export PATH=$HOME/.elixir-install/installs/elixir/$(ls -1 $HOME/.elixir-install/installs/elixir/ | head -1)/bin:$PATH

# Phoenix development aliases
alias phx="mix phx.server"
alias phxd="MIX_ENV=dev mix phx.server"
alias phxt="MIX_ENV=test mix test"
alias ecto="mix ecto"
alias iex="iex -S mix"

# Database shortcuts
alias db.create="mix ecto.create"
alias db.migrate="mix ecto.migrate"
alias db.reset="mix ecto.reset"
alias db.seed="mix ecto.seed"

# Set default directory to app folder (only if starting from home)
if [ "$PWD" = "$HOME" ]; then
    cd ~/app
fi

# Initialize Starship prompt
eval "$(starship init zsh)"
ZSHEOF

    # Install and start code-server (VS Code in browser)
    echo "💻 Installing code-server..."
    curl -fsSL https://code-server.dev/install.sh | sh

    echo "🚀 Starting code-server..."
    code-server --auth none --port 13337 --bind-addr 0.0.0.0:13337 >/tmp/code-server.log 2>&1 &

    # Verify code-server is running
    echo "🔍 Waiting for code-server to start..."
    for i in {1..30}; do
      if timeout 2 bash -c 'cat < /dev/null > /dev/tcp/localhost/13337' 2>/dev/null; then
        echo "✅ Code-server is ready!"
        break
      fi
      echo "⏳ Waiting for code-server... ($i/30)"
      sleep 2
    done

    # Wait for PostgreSQL to be ready
    echo "🔍 Waiting for PostgreSQL..."
    for i in {1..30}; do
      if timeout 2 bash -c 'cat < /dev/null > /dev/tcp/localhost/5432' 2>/dev/null; then
        echo "✅ PostgreSQL is ready!"
        break
      fi
      echo "⏳ Waiting for PostgreSQL... ($i/30)"
      sleep 2
    done

    # Configure dotfiles if URL provided
    if [ -n "${data.coder_parameter.dotfiles_url.value}" ]; then
      echo "🔧 Setting up dotfiles from ${data.coder_parameter.dotfiles_url.value}..."

      # Configure SSH for private repositories if using SSH URL
      if [[ "${data.coder_parameter.dotfiles_url.value}" == git@* ]]; then
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh

        # Check if SSH key secret exists and configure it
        if coder secrets view dotfiles_ssh_key > /dev/null 2>&1; then
          echo "📋 Configuring SSH key for private repository access..."
          coder secrets view dotfiles_ssh_key > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519

          # Add GitHub to known_hosts to avoid interactive prompts
          ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null || true
          ssh-keyscan gitlab.com >> ~/.ssh/known_hosts 2>/dev/null || true

          echo "✅ SSH key configured for dotfiles access"
        else
          echo "⚠️  SSH key secret 'dotfiles_ssh_key' not found. Please add it via: coder secrets create dotfiles_ssh_key"
        fi
      fi

      # Clone dotfiles using coder's built-in command
      echo "📥 Cloning dotfiles repository..."
      if coder dotfiles "${data.coder_parameter.dotfiles_url.value}"; then
        echo "✅ Dotfiles applied successfully!"
      else
        echo "❌ Failed to apply dotfiles. Check repository URL and authentication."
      fi
    else
      echo "📝 No dotfiles repository specified - skipping dotfiles setup"
    fi

    echo "🎉 Environment ready!"
    echo "📊 Database: postgres://postgres:postgres@localhost:5432"
    echo "📁 Default directory: ~/app (automatically set for SSH sessions)"
    echo "🚀 Create Phoenix app: cd ~/app && mix phx.new my_app"
    echo "🗄️ Setup database: mix ecto.create"
    echo "🌐 Start server: mix phx.server"
    echo ""
    echo "📋 Installed versions:"
    echo "  • Erlang: $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell)"
    echo "  • Elixir: $(elixir --version | head -n1)"
    echo "  • Shell: $(zsh --version)"
    echo "📝 Note: Pre-built binaries installed - no compilation required!"
    echo "📝 Note: Databases persist across workspace restarts"
    echo "🐚 Note: zsh with Oh My Zsh and Starship prompt configured with Phoenix aliases"
    echo "📁 Note: ~/app directory created and set as default working directory"
    if [ -n "${data.coder_parameter.dotfiles_url.value}" ]; then
      echo "⚙️  Note: Dotfiles from ${data.coder_parameter.dotfiles_url.value} have been applied"
      echo "🔑 Note: For private repos, ensure 'dotfiles_ssh_key' secret is configured"
    fi
  EOT

  # Metadata for monitoring
  metadata {
    display_name = "CPU Usage"
    key          = "cpu"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage"
    key          = "memory"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "PostgreSQL"
    key          = "postgres"
    script       = "timeout 1 bash -c 'cat < /dev/null > /dev/tcp/localhost/5432' 2>/dev/null && echo '✅ Connected' || echo '❌ Disconnected'"
    interval     = 5
    timeout      = 2
  }

  metadata {
    display_name = "Disk Usage"
    key          = "disk"
    script       = "df -h /home/coder | awk 'NR==2 {print $5}'"
    interval     = 30
    timeout      = 1
  }
}

# Apps
resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:13337"
  icon         = "/icon/code.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 10
  }
}

resource "coder_app" "phoenix" {
  agent_id     = coder_agent.main.id
  slug         = "phoenix"
  display_name = "Phoenix Server"
  url          = "http://localhost:4000"
  icon         = "/icon/phoenix.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:4000"
    interval  = 5
    threshold = 6
  }
}

resource "coder_app" "cursor" {
  agent_id     = coder_agent.main.id
  slug         = "cursor"
  display_name = "Cursor IDE"
  icon         = "https://cursor.com/favicon.ico"
  url          = "cursor://open"
  share        = "owner"
}

# Storage
resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-home"
    namespace = data.kubernetes_namespace.workspace.metadata.0.name
    labels = {
      "coder.workspace.id"   = data.coder_workspace.me.id
      "coder.workspace.name" = data.coder_workspace.me.name
    }
  }

  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${data.coder_parameter.disk_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "postgres_data" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-postgres"
    namespace = data.kubernetes_namespace.workspace.metadata.0.name
    labels = {
      "coder.workspace.id"   = data.coder_workspace.me.id
      "coder.workspace.name" = data.coder_workspace.me.name
    }
  }

  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

# Workspace pod
resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${data.coder_workspace.me.id}"
    namespace = data.kubernetes_namespace.workspace.metadata.0.name
    labels = {
      "coder.workspace.id"   = data.coder_workspace.me.id
      "coder.workspace.name" = data.coder_workspace.me.name
    }
  }


  spec {
    hostname = data.coder_workspace.me.name

    # Simplified security context
    security_context {
      run_as_user     = 1000
      run_as_group    = 1000
      fs_group        = 1000
      run_as_non_root = true
    }

    # Main development container using Coder enterprise base
    container {
      name              = "dev"
      image             = "codercom/enterprise-base:ubuntu"
      image_pull_policy = "Always"
      command           = ["sh", "-c", coder_agent.main.init_script]

      security_context {
        run_as_user = 1000
      }

      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }
      env {
        name  = "DATABASE_URL"
        value = "postgres://postgres:postgres@localhost:5432/postgres"
      }
      env {
        name  = "PGUSER"
        value = "postgres"
      }
      env {
        name  = "PGPASSWORD"
        value = "postgres"
      }
      env {
        name  = "PGHOST"
        value = "localhost"
      }
      env {
        name  = "PGDATABASE"
        value = "postgres"
      }

      env_from {
        secret_ref {
          name = "workspace-secrets"
        }
      }


      resources {
        requests = {
          cpu    = "${data.coder_parameter.cpu.value}"
          memory = "${data.coder_parameter.memory.value}Gi"
        }
        limits = {
          cpu    = "${data.coder_parameter.cpu.value}"
          memory = "${data.coder_parameter.memory.value}Gi"
        }
      }

      volume_mount {
        mount_path = "/home/coder"
        name       = "home"
        read_only  = false
      }
    }

    # PostgreSQL sidecar container (using stable v16)
    container {
      name              = "postgres"
      image             = "postgres:16"
      image_pull_policy = "Always"

      env {
        name  = "POSTGRES_PASSWORD"
        value = "postgres"
      }
      env {
        name  = "POSTGRES_USER"
        value = "postgres"
      }
      env {
        name  = "POSTGRES_DB"
        value = "postgres"
      }
      env {
        name  = "PGDATA"
        value = "/var/lib/postgresql/data/pgdata"
      }

      resources {
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }
        limits = {
          cpu    = "1000m"
          memory = "2Gi"
        }
      }

      volume_mount {
        mount_path = "/var/lib/postgresql/data"
        name       = "postgres-data"
        read_only  = false
      }
    }

    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.home.metadata.0.name
        read_only  = false
      }
    }

    volume {
      name = "postgres-data"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.postgres_data.metadata.0.name
        read_only  = false
      }
    }
  }
}