#!/bin/bash
# Copyright (C) 2015-2023, Wazuh Inc.
# Grype container image vulnerability scanner for Kubernetes environments.
# Adapted for Kubernetes nodes - supports Docker, containerd, and CRI-O runtimes.

GRYPE_BIN=$(command -v grype 2>/dev/null || echo "/usr/local/bin/grype")
TEMPLATE_DIR="/tmp"
TEMPLATE_FILE="$TEMPLATE_DIR/grype-custom.tmpl"

# Verify Grype is installed and executable
if [ ! -x "$GRYPE_BIN" ]; then
  echo "Grype: ERROR - Grype binary not found at $GRYPE_BIN"
  exit 1
fi

# Update Grype vulnerability database before scanning
"$GRYPE_BIN" db update 2>/dev/null

# Create the custom output template for Grype
cat <<'EOL' > "$TEMPLATE_FILE"
"Package","Version Installed","Vulnerability ID","Severity"
{{- range .Matches}}
"{{.Artifact.Name}}","{{.Artifact.Version}}","{{.Vulnerability.ID}}","{{.Vulnerability.Severity}}"
{{- end }}
EOL

# ── Strategy 1: Detect container images via crictl (containerd/CRI-O) ──
images=""

if command -v crictl &>/dev/null; then
  images=$(crictl images -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for img in data.get('images', []):
    for tag in img.get('repoTags', []):
        if '<none>' not in tag:
            print(tag)
" 2>/dev/null)

# ── Strategy 2: Docker runtime (socket + CLI available) ──
elif [ -S /var/run/docker.sock ] && command -v docker &>/dev/null; then
  images=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -v "<none>")

# ── Strategy 3: Docker socket exists but no CLI - try host binary via nsenter ──
elif [ -S /var/run/docker.sock ] && [ -x /host/usr/bin/docker ]; then
  images=$(nsenter --target 1 --mount --uts --ipc --net -- docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -v "<none>")

# ── Strategy 4: Fallback - nsenter to access host's container runtime ──
else
  images=$(nsenter --target 1 --mount --uts --ipc --net -- sh -c '
    if command -v docker &>/dev/null; then
      docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -v "<none>"
    elif command -v crictl &>/dev/null; then
      crictl images 2>/dev/null | tail -n +2 | awk "{print \$1\":\"\$2}" | grep -v "<none>"
    fi
  ' 2>/dev/null)
fi

# ── Strategy 5 (optional): Append ECR registry images for EKS environments ──
# Uncomment and set ECR_IMAGES to scan images directly from an ECR registry:
# ECR_IMAGES="123456789.dkr.ecr.ap-south-1.amazonaws.com/your-app:latest"
# images="$images $ECR_IMAGES"

if [ -z "$images" ]; then
  echo "Grype: No container images found or unable to access container runtime"
  rm -f "$TEMPLATE_FILE"
  exit 0
fi

# Loop through each container image and run Grype scan
for image in $images; do
  grype_output=$("$GRYPE_BIN" "$image" -o template -t "$TEMPLATE_FILE" 2>/dev/null)

  while IFS= read -r line; do
    # Skip the CSV header row
    echo "$line" | grep -q '^"Package"' && continue
    [ -z "$line" ] && continue
    # Prefix with Grype: for Wazuh decoder matching
    echo "Grype:\"$image\",$line"
  done <<< "$grype_output"
done

# Clean up the custom output template
rm -f "$TEMPLATE_FILE"
