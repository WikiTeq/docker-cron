#!/bin/sh

DIR=$(dirname "$0")
. "$DIR/functions.sh"

# Temp cron file paths
CRON_FILE_NEW="/root/crontab.new"
CRON_FILE="/root/crontab"
CRON_LOG_DIR=${CRON_LOG_DIR:-/var/log/cron}

mkdir -p "$CRON_LOG_DIR"

timestamp() {
  date -u "+%Y-%m-%d %H:%M:%S %Z"
}

# Function to extract specific cron job labels from a container
extract_cron_jobs() {
  _container_id=$1
  docker inspect "$_container_id" | jq -r '.[0].Config.Labels | to_entries[] | select(.key | test("^cron\\..*\\.schedule$")) | @base64'
}

# Function to decode base64 encoded JSON entry using BusyBox base64
decode_cron_job() {
  echo "$1" | base64 -d | jq -r '.key,.value'
}

# Function to extract command label for a specific cron job key from a container
extract_cron_command() {
  _container_id=$1
  _job_key=$2
  docker inspect "$_container_id" | jq -r --arg key "$_job_key" '.[0].Config.Labels[$key] // empty'
}

# Get the project name
if [ -z "$COMPOSE_PROJECT_NAME" ]; then
  echo "$(timestamp) COMPOSE_PROJECT_NAME is not set. The service cron will run tasks for all Docker containers."
  containers=$(docker ps -q)
else
  echo "$(timestamp) The service cron will run tasks for Docker containers defined in the COMPOSE_PROJECT_NAME: $COMPOSE_PROJECT_NAME"
  containers=$(docker ps --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" -q)
fi

echo "$(timestamp) Updating cron jobs..."
touch $CRON_FILE_NEW

# Process each container
for container in $containers; do
  cron_jobs=$(extract_cron_jobs "$container")
  if [ -z "$cron_jobs" ]; then
    log "No cron jobs found for container: $container"
  else
    log "Processing container: $container"

    echo "$cron_jobs" | while IFS= read -r job; do
      decoded_job=$(decode_cron_job "$job")
      job_key=$(echo "$decoded_job" | head -n 1 | sed 's/.schedule//' | sed 's/^cron.//')
      job_schedule=$(echo "$decoded_job" | tail -n 1)
      job_command=$(extract_cron_command "$container" "cron.${job_key}.command")

      log "Job key: $job_key"
      log "Job schedule: $job_schedule"
      log "Job command: $job_command"

      # Check if both schedule and command labels are set
      if [ -n "$job_schedule" ] && [ -n "$job_command" ]; then
        target_container=$(docker inspect -f '{{.Name}}' "$container" | cut -c2-) # Remove leading /
        cron_entry="$job_schedule docker exec $target_container sh -c '$job_command' 2>&1 | tee -a $CRON_LOG_DIR/\$(date -u +\%Y-\%m-\%d_\%H-\%M-\%S_\%Z)_$job_key.log"
        echo "$cron_entry" >> $CRON_FILE_NEW # Write in one line to the cron file
        log "Scheduled task for $target_container: $cron_entry"
      else
        echo "$(timestamp) Error: job_schedule or job_command is missing."
      fi
    done
  fi
done

# Check if there are changes
if ! diff -u "$CRON_FILE" "$CRON_FILE_NEW" > /dev/null; then
  # Print the changes in the crontab:
  printf "\n\n%s Changes in the crontab file:\n" "$(timestamp)"
  diff -u "$CRON_FILE" "$CRON_FILE_NEW" | tail -n +3 # Remove the first two lines containing file names

  # Print the updated crontab file
  printf "\n%s Updated crontab file:\n=========================================\n" "$(timestamp)"
  cat "$CRON_FILE_NEW"
  printf "=========================================\n\n"

  # Update the crontab file
  cat "$CRON_FILE_NEW" > "$CRON_FILE"
else
  echo "$(timestamp) No changes detected in crontab file."
fi

rm "$CRON_FILE_NEW"
