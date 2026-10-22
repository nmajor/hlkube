# Temporary host TLS probes

These Pods test kubelet/containerd image-fetch TLS on each node, separately from
Talos's API image resolver. All three image references deliberately do not
exist. No test container is expected to start.

For each node, the two eMudhra image pulls must fail with a certificate error
(`x509: certificate signed by unknown authority`). The valid registry control
must reach the registry and report the nonexistent image/tag (NotFound), proving
valid HTTPS remains usable. DNS errors, timeouts and generic ImagePullBackOff
are inconclusive; inspect each container's detailed waiting message/events.

Before host remediation, a nonexistent-image error for an eMudhra host means the
TLS chain was accepted and the node remains affected. After rebooting with the
committed CA patch, both must change to certificate rejection.

The dedicated Flux Kustomization intentionally has `wait: false` because Pending
Pods are the expected negative-test result. Remove
`clusters/hlkube/talos-host-trust-check.yaml` in Git after collecting results;
Flux prunes its dedicated namespace and Pods. The fixture can remain here for
future explicit audits. Do not add these Pods to normal application health
checks. Do not manually apply or delete the probe resources.
