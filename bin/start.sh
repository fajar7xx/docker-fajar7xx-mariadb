#!/bin/sh

# bin/start.sh — Start MariaDB for a specific environment
# Usage: sh bin/start.sh dev|staging|prod [docker-compose-args]
# Example: sh bin/start.sh dev up -d
#          sh bin/start.sh prod up -d --build

set -e

ENV="${1:-dev}"
shift 2>/dev/null || true
DC_ARGS="${*:-up -d}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

case "$ENV" in
    dev|development)
        ENV_FILE=".env.dev"
        OVERRIDE="docker-compose.dev.yml"
        ENV_NAME="development"
        ;;
    staging|stag)
        ENV_FILE=".env.staging"
        OVERRIDE="docker-compose.staging.yml"
        ENV_NAME="staging"
        ;;
    prod|production)
        ENV_FILE=".env.prod"
        OVERRIDE="docker-compose.prod.yml"
        ENV_NAME="production"
        ;;
    *)
        echo "Error: Unknown environment '$ENV'"
        echo "Usage: $0 dev|staging|prod [docker-compose-args]"
        exit 1
        ;;
esac

ENV_FILE_PATH="$PROJECT_DIR/$ENV_FILE"
OVERRIDE_PATH="$PROJECT_DIR/$OVERRIDE"

if [ ! -f "$ENV_FILE_PATH" ]; then
    echo "Error: Env file not found: $ENV_FILE_PATH"
    exit 1
fi

if [ ! -f "$OVERRIDE_PATH" ]; then
    echo "Error: Override file not found: $OVERRIDE_PATH"
    exit 1
fi

echo "================================================"
echo "MariaDB Docker — $ENV_NAME"
echo "================================================"
echo "Env: $ENV_FILE"
echo "Override: $OVERRIDE"
echo "Command: docker compose -f docker-compose.yml -f $OVERRIDE --env-file $ENV_FILE $DC_ARGS"
echo "================================================"
echo ""

docker compose \
    -f docker-compose.yml \
    -f "$OVERRIDE" \
    --env-file "$ENV_FILE" \
    $DC_ARGS
