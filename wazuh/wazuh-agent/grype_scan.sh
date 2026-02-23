#!/bin/bash
# Copyright (C) 2015-2023, Wazuh Inc.
# Grype container image vulnerability scanner for Kubernetes environments.
# Adapted for Kubernetes nodes - supports Docker and containerd runtimes.

GRYPE_BIN="/var/ossec/custom-script/grype"
TEMPLATE_DIR="/tmp"
TEMPLATE_FILE="$TEMPLATE_DIR/grype-custom.tmpl"

# Create the custom output template for Grype
cat <<'EOL' > "$TEMPLATE_FILE"
"Package","Version Installed","Vulnerability ID","Severity"
{{- range .Matches}}
"{{.Artifact.Name}}","{{.Artifact.Version}}","{{.Vulnerability.ID}}","{{.Vulnerability.Severity}}"
{{- end }}
EOL

# Detect container images based on available runtime
images=""

if [ -S /var/run/docker.sock ] && command -v docker &>/dev/null; then
  # Docker runtime
  images=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -v "<none>")
elif [ -S /var/run/docker.sock ]; then
  # Docker socket exists but no docker CLI - try the host binary
  if [ -x /host/usr/bin/docker ]; then
    images=$(nsenter --target 1 --mount --uts --ipc --net -- docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -v "<none>")
  fi
elif command -v crictl &>/dev/null; then
  # Containerd/CRI-O runtime with crictl
  images=$(crictl images -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for img in data.get('images', []):
    for tag in img.get('repoTags', []):
        print(tag)
" 2>/dev/null)
else
  # Fallback: try nsenter to access host's container runtime
  images=$(nsenter --target 1 --mount --uts --ipc --net -- sh -c '
    if command -v docker &>/dev/null; then
      docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -v "<none>"
    elif command -v crictl &>/dev/null; then
      crictl images 2>/dev/null | tail -n +2 | awk "{print \$1\":\"\$2}" | grep -v "<none>"
    fi
  ' 2>/dev/null)
fi

if [ -z "$images" ]; then
  echo "Grype: No container images found or unable to access container runtime"
  rm -f "$TEMPLATE_FILE"
  exit 0
fi

# Loop through each container image and run Grype scan
for image in $images; do
  grype_output=$("$GRYPE_BIN" "$image" -o template -t "$TEMPLATE_FILE" 2>/dev/null)

  while IFS= read -r line; do
    # Prepend image name with quotes and comma
    formatted_line=Grype:"\"$image\","$line
    echo "$formatted_line"
  done <<< "$grype_output"
done

# Clean up the custom output template
rm -f "$TEMPLATE_FILE"
