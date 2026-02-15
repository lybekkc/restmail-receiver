#!/bin/bash

# Migrate from hostPath to PVC
# This script helps you switch to persistent storage

set -e

echo "🔄 Restmail Kubernetes Storage Migration"
echo "========================================="
echo ""
echo "This will:"
echo "  1. Backup existing emails (if any)"
echo "  2. Delete current deployment"
echo "  3. Create PVCs"
echo "  4. Deploy with persistent storage"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Get current pod name
POD_NAME=$(kubectl get pods -l app=restmail-receiver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

# Backup emails if pod exists
if [ -n "$POD_NAME" ]; then
    echo ""
    echo "1️⃣ Backing up existing emails..."
    BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    # Try to copy emails
    if kubectl exec "$POD_NAME" -- test -d /var/mail/restmail/incoming 2>/dev/null; then
        echo "   Creating tar archive in pod..."
        kubectl exec "$POD_NAME" -- tar czf /tmp/backup.tar.gz -C /var/mail/restmail incoming/ 2>/dev/null || true

        echo "   Copying to local machine..."
        kubectl cp "$POD_NAME:/tmp/backup.tar.gz" "$BACKUP_DIR/emails-backup.tar.gz" 2>/dev/null || true

        if [ -f "$BACKUP_DIR/emails-backup.tar.gz" ]; then
            echo "   ✅ Backup saved to: $BACKUP_DIR/emails-backup.tar.gz"
            cd "$BACKUP_DIR"
            tar xzf emails-backup.tar.gz
            cd - > /dev/null
            echo "   ✅ Extracted to: $BACKUP_DIR/incoming/"
        else
            echo "   ⚠️  No emails to backup or backup failed"
        fi
    else
        echo "   ⚠️  No emails directory found"
    fi
else
    echo "   ⚠️  No running pod found, skipping backup"
fi

echo ""
echo "2️⃣ Deleting current deployment..."
kubectl delete -f deploy/restmail-k8s.yaml --ignore-not-found=true
echo "   ✅ Deployment deleted"

echo ""
echo "3️⃣ Waiting for pod to terminate..."
sleep 5

echo ""
echo "4️⃣ Creating PVCs and deploying with persistent storage..."
kubectl apply -f deploy/restmail-k8s-pvc.yaml
echo "   ✅ Deployment created"

echo ""
echo "5️⃣ Waiting for pod to be ready..."
kubectl wait --for=condition=ready pod -l app=restmail-receiver --timeout=60s

NEW_POD=$(kubectl get pods -l app=restmail-receiver -o jsonpath='{.items[0].metadata.name}')
echo "   ✅ Pod ready: $NEW_POD"

# Restore backup if exists
if [ -d "$BACKUP_DIR/incoming" ] && [ "$(ls -A $BACKUP_DIR/incoming 2>/dev/null)" ]; then
    echo ""
    echo "6️⃣ Restoring emails to new pod..."

    # Copy backup back to pod
    for email in "$BACKUP_DIR/incoming"/*.eml; do
        if [ -f "$email" ]; then
            filename=$(basename "$email")
            echo "   Restoring: $filename"
            kubectl cp "$email" "$NEW_POD:/var/mail/restmail/incoming/$filename"
        fi
    done

    EMAIL_COUNT=$(ls "$BACKUP_DIR/incoming"/*.eml 2>/dev/null | wc -l)
    echo "   ✅ Restored $EMAIL_COUNT emails"
fi

echo ""
echo "========================================="
echo "✅ Migration Complete!"
echo ""
echo "Your restmail-receiver is now using PersistentVolumeClaims."
echo "Emails will persist across pod restarts and node failures."
echo ""
echo "Check status:"
echo "  kubectl get pods -l app=restmail-receiver"
echo "  kubectl get pvc"
echo ""
echo "Test it:"
echo "  ./test-k8s-on-vps.sh"
echo ""

if [ -d "$BACKUP_DIR" ]; then
    echo "Backup location: $BACKUP_DIR"
    echo ""
fi

