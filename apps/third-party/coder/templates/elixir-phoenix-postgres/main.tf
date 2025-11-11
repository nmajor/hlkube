terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5.0"
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

data "coder_workspace_owner" "me" {
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
  default      = 4
  type         = "number"
  mutable      = true
  validation {
    min = 1
    max = 6
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "Amount of memory in GB"
  default      = 8
  type         = "number"
  mutable      = true
  validation {
    min = 4
    max = 12
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Disk Size (GB)"
  description  = "Size of /home/coder for code, deps, DB. 20-30GB recommended for Phoenix development."
  default      = 20
  type         = "number"
  mutable      = true
  validation {
    min       = 10
    max       = 100
    monotonic = "increasing"
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

    # Start Tailscale for direct SSH access
    echo "🔌 Starting Tailscale..."
    sudo mkdir -p /var/lib/tailscale /var/run/tailscale
    sudo tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock --tun=userspace-networking >/tmp/tailscaled.log 2>&1 &

    # Wait for tailscaled to start
    sleep 3

    # Authenticate with unique hostname
    WORKSPACE_HOSTNAME="${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
    echo "🌐 Connecting to Tailscale as: $WORKSPACE_HOSTNAME"
    sudo -E tailscale up \
      --authkey="$TAILSCALE_AUTHKEY" \
      --hostname="$WORKSPACE_HOSTNAME" \
      --ssh \
      --accept-routes=false \
      --advertise-tags=tag:coder-workspace

    echo "✅ Tailscale connected! SSH available at: $WORKSPACE_HOSTNAME.kooka-woodpecker.ts.net"

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
  icon         = "https://icon.icepanel.io/Technology/svg/Phoenix-Framework.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:4000"
    interval  = 5
    threshold = 20
  }
}

# Cursor Desktop module for one-click workspace access
module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.3.2"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/app"
}

resource "coder_app" "crawl4ai" {
  agent_id     = coder_agent.main.id
  slug         = "crawl4ai"
  display_name = "Crawl4AI"
  url          = "http://localhost:11235"
  icon         = "/icon/search.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:11235/health"
    interval  = 5
    threshold = 24
  }
}

resource "coder_app" "dataforseo_mcp" {
  agent_id     = coder_agent.main.id
  slug         = "dataforseo-mcp"
  display_name = "DataForSEO MCP"
  url          = "http://localhost:11577"
  icon         = "/icon/terminal.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:11577"
    interval  = 10
    threshold = 6
  }
}

resource "coder_app" "playwright_mcp" {
  agent_id     = coder_agent.main.id
  slug         = "playwright-mcp"
  display_name = "Playwright MCP"
  url          = "http://localhost:11666"
  icon         = "/icon/browser.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:11666"
    interval  = 10
    threshold = 6
  }
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
      image             = "ghcr.io/nmajor/coder-workspace:latest"
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
      env {
        name  = "CRAWL4AI_MCP_URL"
        value = "http://localhost:11235"
      }
      env {
        name  = "DATAFORSEO_MCP_URL"
        value = "http://localhost:11577"
      }
      env {
        name  = "PLAYWRIGHT_MCP_URL"
        value = "http://localhost:11666"
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

    # PostgreSQL with PostGIS sidecar container (using stable v17)
    container {
      name              = "postgres"
      image             = "postgis/postgis:17-3.5"
      image_pull_policy = "IfNotPresent"

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

    # Crawl4AI sidecar container
    container {
      name              = "crawl4ai"
      image             = "unclecode/crawl4ai:latest"
      image_pull_policy = "IfNotPresent"

      security_context {
        run_as_user     = 999
        run_as_non_root = false
      }

      # Inject only secrets intended for Crawl4AI (prefix: CRAWL4AI_)
      dynamic "env" {
        for_each = { for k, v in data.kubernetes_secret.workspace_secrets.data : k => v if startswith(k, "CRAWL4AI_") }
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

      # The server listens on 11235; ensure it binds 0.0.0.0 inside the pod
      port {
        container_port = 11235
      }

      resources {
        requests = {
          cpu    = "200m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "2Gi"
        }
      }

      volume_mount {
        mount_path = "/dev/shm"
        name       = "crawl4ai-shm"
        read_only  = false
      }
    }

    # Playwright MCP sidecar container
    container {
      name              = "playwright-mcp"
      image             = "mcp/playwright:latest"
      image_pull_policy = "IfNotPresent"
      command           = ["node"]
      args              = ["cli.js", "--headless", "--browser", "chromium", "--no-sandbox", "--port", "11666"]

      security_context {
        run_as_user = 1000
      }

      # Inject only secrets intended for Playwright (prefix: PLAYWRIGHT_)
      dynamic "env" {
        for_each = { for k, v in data.kubernetes_secret.workspace_secrets.data : k => v if startswith(k, "PLAYWRIGHT_") }
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

      resources {
        requests = {
          cpu    = "200m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "2Gi"
        }
      }

      volume_mount {
        mount_path = "/dev/shm"
        name       = "playwright-shm"
        read_only  = false
      }

      port {
        container_port = 11666
      }
    }

    # DataForSEO MCP sidecar container
    container {
      name              = "dataforseo-mcp"
      image             = "dataforseo/mcp:latest"
      image_pull_policy = "IfNotPresent"

      security_context {
        run_as_user = 1000
      }

      # Inject only secrets intended for DataForSEO (prefix: DATAFORSEO_)
      dynamic "env" {
        for_each = { for k, v in data.kubernetes_secret.workspace_secrets.data : k => v if startswith(k, "DATAFORSEO_") }
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

      # Use a fixed non-standard internal port supported via PORT env
      env {
        name  = "PORT"
        value = "11577"
      }

      port {
        container_port = 11577
      }

      resources {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
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

    # Memory-backed /dev/shm for Crawl4AI (equivalent to --shm-size=1g)
    volume {
      name = "crawl4ai-shm"
      empty_dir {
        medium     = "Memory"
        size_limit = "1Gi"
      }
    }

    # Memory-backed /dev/shm for Playwright (browser needs large shared memory)
    volume {
      name = "playwright-shm"
      empty_dir {
        medium     = "Memory"
        size_limit = "1Gi"
      }
    }
  }
}
