#!/bin/bash

# Find all .secret files and seal them
find . -name "*.secret" | while read secretfile; do
  sealedfile=${secretfile%.secret}.sealed.yaml
  
  # Seal if sealed file doesn't exist or if secret file is newer
  if [ ! -f "$sealedfile" ] || [ "$secretfile" -nt "$sealedfile" ]; then
    echo "Sealing $secretfile to $sealedfile..."
    kubeseal --format yaml --controller-name=sealed-secrets-controller \
      --controller-namespace=sealed-secrets < $secretfile > $sealedfile
  else
    echo "Skipping $secretfile (sealed version exists and is up to date)"
  fi
done 