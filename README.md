

Folder structure:
```t
hlkube-flux/
├── clusters/
│   └── hlkube/              # Root Flux watches for this cluster (created by bootstrap)
│       ├── flux-system/       # Flux components (managed by bootstrap)
│       │   ├── gotk-components.yaml
│       │   ├── gotk-sync.yaml
│       │   └── kustomization.yaml
│       ├── infrastructure.yaml  # Top-level Kustomization for infra components
│       ├── apps.yaml          # Top-level Kustomization for applications
│       └── README.md          # Info about this specific cluster config
├── infrastructure/          # Cluster-wide infrastructure services (non-app specific)
│   ├── sources/             # Optional: GitRepository/HelmRepository sources
│   │   ├── kustomization.yaml
│   │   └── longhorn.yaml    # Example HelmRepository for Longhorn
│   │   └── traefik.yaml     # Example HelmRepository for Traefik
│   ├── cert-manager/        # Example: Cert-Manager manifests/HelmRelease
│   │   └── kustomization.yaml
│   ├── longhorn/            # Longhorn manifests/HelmRelease
│   │   └── kustomization.yaml
│   ├── traefik/             # Traefik manifests/HelmRelease
│   │   └── kustomization.yaml
│   ├── tailscale/           # Tailscale operator/subnet router manifests
│   │   └── kustomization.yaml
│   └── kustomization.yaml     # Kustomization linking all infra/* subdirs
├── apps/                    # Application deployments
│   ├── sources/             # Optional: App-specific Git/Helm sources
│   │   └── kustomization.yaml
│   ├── third-party/         # Apps built by others (e.g., monitoring stack, databases if not per-app)
│   │   ├── postgres-operator/ # Example
│   │   │   └── kustomization.yaml
│   │   └── kustomization.yaml # Kustomization linking all third-party/* subdirs
│   ├── custom/              # Apps you have built
│   │   ├── my-phoenix-app/  # Configs for your Phoenix app (Deployment, Service, IngressRoute, DB claim/instance etc.)
│   │   │   └── kustomization.yaml
│   │   ├── my-rails-app/    # Configs for your Rails app
│   │   │   └── kustomization.yaml
│   │   └── kustomization.yaml # Kustomization linking all custom/* subdirs
│   └── kustomization.yaml     # Kustomization linking third-party/ and custom/
└── README.md                # Overall repository README
```

---
❯ kubectl logs -n longhorn-system longhorn-manager-b7tsc -c longhorn-manager | cat
time="2025-04-17T21:50:39Z" level=fatal msg="Error starting manager: failed to check environment, please make sure you have iscsiadm/open-iscsi installed on the host: failed to execute: /usr/bin/nsenter [nsenter --mount=/host/proc/79679/ns/mnt --net=/host/proc/79679/ns/net iscsiadm --version], output , stderr nsenter: failed to execute iscsiadm: No such file or directory\n: exit status 127" func=main.main.DaemonCmd.func3 file="daemon.go:105"

https://www.talos.dev/v1.9/kubernetes-guides/configuration/storage/
https://www.reddit.com/r/kubernetes/comments/1hwietr/problem_with_adding_extensions_to_talos/