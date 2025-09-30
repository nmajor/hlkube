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

provider "kubernetes" {
  config_path = null
}

data "kubernetes_secret" "workspace_secrets" {
  metadata {
    name      = "workspace-secrets"
    namespace = local.namespace
  }
}

# Reference existing namespace
data "kubernetes_namespace" "workspace" {
  metadata {
    name = local.namespace
  }
}

# Coder agent configuration
resource "coder_agent" "main" {
  arch                    = data.coder_provisioner.me.arch
  os                      = "linux"
  startup_script_behavior = "blocking"
  startup_script = <<-EOT
    set -e

    # Install PostgreSQL client for connection testing
    echo "📦 Installing PostgreSQL client..."
    sudo apt-get -o DPkg::Lock::Timeout=300 update -qq
    sudo apt-get -o DPkg::Lock::Timeout=300 install -y -qq postgresql-client >/dev/null 2>&1

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
    for i in {1..60}; do
        if timeout 2 bash -c 'cat < /dev/null > /dev/tcp/localhost/5432' 2>/dev/null; then
        echo "✅ PostgreSQL port is open, checking if accepting connections..."
        # Use pg_isready for proper readiness check
        if pg_isready -h localhost -p 5432 -U postgres >/dev/null 2>&1; then
            echo "✅ PostgreSQL is ready and accepting connections!"
            # Verify we can actually query
            if PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "SELECT 1" >/dev/null 2>&1; then
                echo "✅ PostgreSQL query test successful!"
                break
            else
                echo "⏳ PostgreSQL ready but query failed... ($i/60)"
            fi
        else
            echo "⏳ PostgreSQL port open but not ready yet... ($i/60)"
        fi
        else
        echo "⏳ Waiting for PostgreSQL port... ($i/60)"
        fi
        sleep 2
    done
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

# Dotfiles module for personalized development environment
module "dotfiles" {
  count                = data.coder_workspace.me.start_count
  source               = "registry.coder.com/modules/dotfiles/coder"
  version              = "1.0.14"
  agent_id             = coder_agent.main.id
  default_dotfiles_uri = "https://github.com/nmajor/coder-phoenix-dotfiles"
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
  display_name = "Cursor Desktop"
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

      dynamic "env" {
        for_each = data.kubernetes_secret.workspace_secrets.data
        content {
          name = env.key

          value_from {
            secret_key_ref {
              name = data.kubernetes_secret.workspace_secrets.metadata[0].name  # "workspace-secrets"
              key  = env.key
            }
          }
        }
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

    # PostgreSQL with TimescaleDB sidecar container (using stable v17)
    container {
      name              = "postgres"
      image             = "timescale/timescaledb:latest-pg17"
      image_pull_policy = "Always"

      security_context {
        run_as_user = 1000
      }

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