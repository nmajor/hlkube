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

provider "coder" {
  url = "http://coder.coder.svc.cluster.local"
}

data "coder_provisioner" "me" {
}

data "coder_workspace" "me" {
}

# Hardcoded namespace for workspace separation
locals {
  namespace = "coder-workspaces"
}

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
  description  = "Size of /home/coder (covers code, deps, DB, Claude artifacts). Min 10Gi for light use; 20-30Gi recommended for Phoenix/Ash/Claude."
  default      = 20
  type         = "number"
  mutable      = false
  validation {
    min = 10
    max = 100
  }
}

data "coder_parameter" "elixir_image" {
  name         = "elixir_image"
  display_name = "Elixir Docker Image"
  description  = "Elixir image tag (e.g., 1.18.4-otp-28, 1.17-otp-26). View available tags: https://hub.docker.com/_/elixir/tags"
  default      = "1.18.4-otp-28"
  type         = "string"
  validation {
    regex = "^\\d+\\.\\d+(\\.(\\d+))?(-otp-\\d+)?(-\\w+)?$"
    error = "Please use a valid Elixir tag format like '1.18.4-otp-28' or '1.17-otp-26'"
  }
}

data "coder_parameter" "postgres_image" {
  name         = "postgres_image"
  display_name = "PostgreSQL Docker Image"
  description  = "PostgreSQL image tag (e.g., 17, 16.1, 15-alpine). View available tags: https://hub.docker.com/_/postgres/tags"
  default      = "17"
  type         = "string"
  validation {
    regex = "^\\d+(\\.(\\d+))?(-\\w+)?$"
    error = "Please use a valid PostgreSQL tag format like '17', '16.1', or '15-alpine'"
  }
}

provider "kubernetes" {
  config_path = null
}

# Reference existing namespace created by Flux GitOps
data "kubernetes_namespace" "workspace" {
  metadata {
    name = local.namespace
  }
}

# Create ServiceAccount for workspace
resource "kubernetes_service_account" "workspace" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}"
    namespace = data.kubernetes_namespace.workspace.metadata.0.name
    labels = {
      "coder.workspace.id"   = data.coder_workspace.me.id
      "coder.workspace.name" = data.coder_workspace.me.name
    }
  }
}

# Create Role for workspace permissions
resource "kubernetes_role" "workspace" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}"
    namespace = data.kubernetes_namespace.workspace.metadata.0.name
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumeclaims", "pods", "services", "secrets", "events"]
    verbs      = ["create", "delete", "deletecollection", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["create", "delete", "deletecollection", "get", "list", "patch", "update", "watch"]
  }
}

# Bind Role to ServiceAccount
resource "kubernetes_role_binding" "workspace" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}"
    namespace = data.kubernetes_namespace.workspace.metadata.0.name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.workspace.metadata.0.name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.workspace.metadata.0.name
    namespace = data.kubernetes_namespace.workspace.metadata.0.name
  }
}

resource "coder_agent" "main" {
  arch                     = data.coder_provisioner.me.arch
  os                       = "linux"
  startup_script_behavior  = "blocking"
  startup_script = <<-EOT
    #!/bin/bash
    set -eo pipefail  # Remove 'u' flag to allow undefined variables

    echo "🚀 Starting Elixir Phoenix development environment setup..."

    # Fix user environment immediately
    export USER=coder
    export HOME=/home/coder

    # Ensure home directory exists (don't try to change ownership in container)
    mkdir -p /home/coder

    # Set environment for current session
    cd /home/coder

    # Install Node.js/npm via binary download (no root needed)
    echo "📥 Installing Node.js v20..."
    cd /tmp
    if curl -fsSL https://nodejs.org/dist/v20.15.0/node-v20.15.0-linux-x64.tar.xz | tar -xJ; then
        export PATH="/tmp/node-v20.15.0-linux-x64/bin:$PATH"
        echo 'export PATH="/tmp/node-v20.15.0-linux-x64/bin:$PATH"' >> /home/coder/.bashrc
        echo "✅ Node.js installed successfully"
    else
        echo "⚠️ Node.js installation failed, continuing..."
    fi

    # Wait for PostgreSQL using network connectivity check
    echo "🔍 Waiting for PostgreSQL..."
    for i in {1..30}; do
      if timeout 2 bash -c 'cat < /dev/null > /dev/tcp/localhost/5432' 2>/dev/null; then
        echo "✅ PostgreSQL is ready!"
        break
      fi
      echo "⏳ Waiting for PostgreSQL... ($i/30)"
      sleep 2
    done

    # Database server ready for Phoenix apps
    echo "🗄️ Database server ready for Phoenix development..."

    # Install Elixir tools
    echo "⚗️ Installing Elixir tools..."
    # Create .mix directory structure (required for container environment)
    mkdir -p /home/coder/.mix/archives
    export MIX_HOME=/home/coder/.mix
    mix local.hex --force
    mix local.rebar --force
    mix archive.install hex phx_new --force

    # Install code-server using official method from Coder docs
    echo "💻 Installing code-server..."
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server
    echo "✅ Code-server installed successfully"

    # Start code-server in background (official Coder example pattern)
    echo "🖥️ Starting code-server..."
    /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &
    echo "✅ Code-server started on port 13337"

    echo "🎉 Setup complete! Ready for Phoenix development!"
    echo "📊 Database Server: postgres://postgres:postgres@localhost:5432"
    echo "🐘 PostgreSQL Version: Available via container"
    echo "⚗️ Elixir Version: Available via container"
    echo "🚀 Create new Phoenix app: mix phx.new my_app"
    echo "🗄️ Create database: mix ecto.create"
  EOT

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

# Cursor Desktop Integration
module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.0.19"
  agent_id = coder_agent.main.id
}

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
    threshold = 6
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

resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${data.coder_workspace.me.id}"
    namespace = data.kubernetes_namespace.workspace.metadata.0.name
    labels = {
      "coder.workspace.id"   = data.coder_workspace.me.id
      "coder.workspace.name" = data.coder_workspace.me.name
    }
    annotations = {
      "coder.workspace.id" = data.coder_workspace.me.id
    }
  }

  spec {
    service_account_name = kubernetes_service_account.workspace.metadata.0.name
    security_context {
      run_as_user = 1000
      fs_group    = 1000
      run_as_non_root = true
    }

    container {
      name              = "dev"
      image             = "elixir:${data.coder_parameter.elixir_image.value}"
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
        name  = "USER"
        value = "coder"
      }
      env {
        name  = "SHELL"
        value = "/bin/bash"
      }
      env {
        name  = "DATABASE_URL"
        value = "postgres://postgres:postgres@localhost:5432"
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

    container {
      name              = "postgres"
      image             = "postgres:${data.coder_parameter.postgres_image.value}"
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