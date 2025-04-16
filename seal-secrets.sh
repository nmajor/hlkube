#!/bin/bash

# Find all .secret files and seal them
find . -name "*.secret" | while read secretfile; do
  sealedfile=${secretfile%.secret}.sealed.yaml
  echo "Sealing $secretfile to $sealedfile..."
  kubeseal --format yaml --controller-name=sealed-secrets-controller \
    --controller-namespace=sealed-secrets < $secretfile > $sealedfile
done 