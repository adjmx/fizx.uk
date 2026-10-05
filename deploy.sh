#!/bin/bash
# deploy.sh - Deploy fizx.uk to your server
set -e

SERVER="fizx.uk"   # a Host alias in ~/.ssh/config: the user, port and key live there
REMOTE_PATH="/var/www/fizx.uk"
LOCAL_DIST="./build"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

export PATH="/Users/x22/.nvm/versions/node/v22.20.0/bin:$PATH"

echo "📦 Building fizx.uk..."
npm ci --silent
rm -rf .svelte-kit build
npm run build

[ ! -f "$LOCAL_DIST/404.html" ] && echo "❌ build/404.html missing" && exit 1
echo "✅ Build done"

echo "🚀 Deploying..."
# nginx only reads, so force world-readable modes rather than copying whatever
# the local files happen to have. --chmod needs real rsync (not macOS openrsync).
rsync -avz --delete --chmod=D755,F644 \
  --exclude='.DS_Store' --exclude='*.log' --exclude='.git' \
  "$LOCAL_DIST/" "$SERVER:$REMOTE_PATH/"

# Nothing runs on the server after the copy. Root login is off there and sudo
# asks for a password; the webroot belongs to the deploy user, and the vhost
# already serves /404.html for unknown paths (this script used to patch that).
echo "✅ https://fizx.uk"
