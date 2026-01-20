#!/bin/bash
# List available LWS operator bundle versions
echo "Available bundle versions:"
skopeo list-tags docker://registry.redhat.io/leader-worker-set/lws-operator-bundle 2>/dev/null | \
    grep -oP '"[0-9]+\.[0-9]+[^"]*"' | tr -d '"' | grep -v sha256 | sort -V
