

Trigger a new flux reconcile
```bash
flux reconcile source git flux-system
```

Watch a new helm release
```bash
flux get helmreleases -n longhorn-system -w
```

