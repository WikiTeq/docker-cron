#!/bin/sh
DIR=$(dirname "$0")
. "$DIR/functions.sh"

# Create empty crontab file
true > /root/crontab

if [ -z "$COMPOSE_PROJECT_NAME" ]; then
  echo "$(timestamp) | The COMPOSE_PROJECT_NAME variable is required but not set."
  exit 1
fi

if isTrue "$DEBUG"; then
    supercronic -debug -inotify /root/crontab &
else
    supercronic -inotify /root/crontab &
fi

# Function to update cron jobs based on container labels
update_cron() {
  /usr/local/bin/update_cron.sh
}

# File to indicate if an update is already scheduled
UPDATE_SCHEDULED="/tmp/update_scheduled.lock"

# Wrapper function to handle concurrent events
handle_event() {
  if [ -f "$UPDATE_SCHEDULED" ]; then
    # If update is already scheduled or running, mark the need for a subsequent update
    touch "$UPDATE_SCHEDULED"
  else
    # Schedule the update
    touch "$UPDATE_SCHEDULED"
    while [ -f "$UPDATE_SCHEDULED" ]; do
      # Do not rush
      sleep 2
      rm -f "$UPDATE_SCHEDULED"
      update_cron
    done
  fi
}

# Initial update
handle_event &

# Define a function to handle cleanup on SIGTERM
cleanup() {
  echo "Received SIGTERM, cleaning up..."
  rm -f "$UPDATE_SCHEDULED"
  exit 0
}

# Set a trap to catch the SIGTERM signal
trap 'cleanup' TERM

# Construct docker events command with base filters
DOCKER_EVENTS_CMD="docker events --filter 'event=start' --filter 'event=die' --filter 'event=destroy'"

# If COMPOSE_PROJECT_NAME is defined, filter by that project
if [ -n "$COMPOSE_PROJECT_NAME" ]; then
  DOCKER_EVENTS_CMD="$DOCKER_EVENTS_CMD --filter label=com.docker.compose.project=$COMPOSE_PROJECT_NAME"
fi

# Optionally filter by cron.enabled=true if CRON_FILTER_BY_LABEL is set
if [ "$CRON_FILTER_BY_LABEL" = "true" ]; then
  DOCKER_EVENTS_CMD="$DOCKER_EVENTS_CMD --filter label=cron.enabled=true"
fi

# Watch for Docker events and update cron jobs
eval "$DOCKER_EVENTS_CMD" | while IFS= read -r LINE; do
  log "Docker event detected: $LINE"
  handle_event &
done
