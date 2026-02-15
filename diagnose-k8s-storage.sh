#!/bin/bash

# Diagnose Kubernetes Storage Issue
# Run this on your VPS to check why emails aren't persisting

echo "🔍 Diagnosing Kubernetes Storage Issue..."
echo "==========================================="
echo ""

# Get pod name
POD_NAME=$(kubectl get pods -l app=restmail-receiver -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD_NAME" ]; then
    echo "❌ No pod found!"
    exit 1
fi
echo "📦 Pod: $POD_NAME"
echo ""

# Check deployment volumes
echo "1️⃣ Checking volume configuration..."
VOLUME_TYPE=$(kubectl get deployment restmail-receiver -o jsonpath='{.spec.template.spec.volumes[0]}')
echo "   Volume config: $VOLUME_TYPE"

if echo "$VOLUME_TYPE" | grep -q "hostPath"; then
    echo "   ⚠️  Using hostPath (not PVC)"
    echo "   Files are stored on the node at: /var/mail/restmail"
    echo "   This won't persist if pod moves to another node!"
elif echo "$VOLUME_TYPE" | grep -q "persistentVolumeClaim"; then
    echo "   ✅ Using PVC (persistent storage)"
else
    echo "   ❌ Unknown volume type"
fi
echo ""

# Check PVCs
echo "2️⃣ Checking PersistentVolumeClaims..."
if kubectl get pvc restmail-mail-pvc &>/dev/null; then
    echo "   ✅ PVC exists: restmail-mail-pvc"
    kubectl get pvc restmail-mail-pvc
else
    echo "   ❌ PVC not found: restmail-mail-pvc"
    echo "   You need to create PVC or use restmail-k8s-pvc.yaml"
fi
echo ""

# Check what's mounted in the pod
echo "3️⃣ Checking actual mounts in pod..."
kubectl exec "$POD_NAME" -- df -h /var/mail/restmail 2>/dev/null || echo "   ❌ Mount check failed"
echo ""

# Check if emails exist in pod
echo "4️⃣ Checking emails inside pod..."
EMAIL_COUNT=$(kubectl exec "$POD_NAME" -- sh -c 'ls /var/mail/restmail/incoming/*.eml 2>/dev/null | wc -l' 2>/dev/null || echo "0")
echo "   Emails in pod: $EMAIL_COUNT"

if [ "$EMAIL_COUNT" -gt "0" ]; then
    echo "   Latest emails:"
    kubectl exec "$POD_NAME" -- sh -c 'ls -lh /var/mail/restmail/incoming/*.eml | tail -5'
fi
echo ""

# Check node where pod is running
echo "5️⃣ Checking node location..."
NODE=$(kubectl get pod "$POD_NAME" -o jsonpath='{.spec.nodeName}')
echo "   Pod is running on node: $NODE"
echo ""

# If using hostPath, check on node
if echo "$VOLUME_TYPE" | grep -q "hostPath"; then
    echo "6️⃣ Checking hostPath on node (if this is a single-node cluster)..."
    if [ -d "/var/mail/restmail/incoming" ]; then
        echo "   ✅ Directory exists on this node"
        ls -lh /var/mail/restmail/incoming/ 2>/dev/null || echo "   (empty or permission issue)"
    else
        echo "   ❌ Directory not found on this node"
        echo "   Note: You might be SSH'd to a different node than where the pod runs"
    fi
fi
echo ""

# Check volume mounts in pod
echo "7️⃣ Checking volume mounts inside pod..."
kubectl exec "$POD_NAME" -- mount | grep -E '(mail|log)' || echo "   (No mail/log mounts found)"
echo ""

echo "==========================================="
echo "📊 Summary:"
echo ""

if echo "$VOLUME_TYPE" | grep -q "persistentVolumeClaim"; then
    echo "✅ Using PVC - data should persist"
    echo ""
    echo "To access emails:"
    echo "  kubectl exec $POD_NAME -- ls /var/mail/restmail/incoming/"
    echo "  kubectl exec $POD_NAME -- cat /var/mail/restmail/incoming/<filename>.eml"
    echo ""
elif echo "$VOLUME_TYPE" | grep -q "hostPath"; then
    echo "⚠️  Using hostPath - data only persists on the node"
    echo ""
    echo "Current setup: Files are at /var/mail/restmail on node: $NODE"
    echo ""
    echo "To access emails (if on same node):"
    echo "  ls /var/mail/restmail/incoming/"
    echo ""
    echo "To switch to PVC (recommended):"
    echo "  1. kubectl delete -f deploy/restmail-k8s.yaml"
    echo "  2. kubectl apply -f deploy/restmail-k8s-pvc.yaml"
    echo ""
fi

echo "To copy emails from pod to local:"
echo "  kubectl exec $POD_NAME -- tar czf /tmp/emails.tar.gz /var/mail/restmail/incoming/"
echo "  kubectl cp $POD_NAME:/tmp/emails.tar.gz ./emails.tar.gz"
echo ""

