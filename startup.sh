#!/bin/sh
DIR=$(dirname "$0")
. "$DIR/functions.sh"

# Create empty crontab file
true > /root/crontab

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

# Watch for Docker events and update cron jobs
docker events --filter 'event=start' --filter 'event=die' --filter 'event=destroy' | while IFS= read -r LINE; do
  log "Docker event detected: $LINE"
  handle_event &
done
