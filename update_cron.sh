#!/bin/sh

DIR=$(dirname "$0")
. "$DIR/functions.sh"

# Temp cron file paths with unique identifiers to prevent conflicts
CRON_FILE_TEST="/tmp/cron_test_$$"
CRON_FILE_NEW="/tmp/crontab_new_$$"
CRON_FILE="/root/crontab"
CRON_LOG_DIR=${CRON_LOG_DIR:-/var/log/cron}

# Ensure cleanup on exit
cleanup() {
  rm -f "$CRON_FILE_TEST" "$CRON_FILE_NEW"
}
trap cleanup EXIT

mkdir -p "$CRON_LOG_DIR"

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

# Consolidated debug message for COMPOSE_PROJECT_NAME and FILTER variables
if [ -z "$COMPOSE_PROJECT_NAME" ] && [ -z "$FILTER" ]; then
  echo "$(timestamp) | Neither COMPOSE_PROJECT_NAME nor FILTER is defined. At least one is required."
  exit 1
elif [ -z "$COMPOSE_PROJECT_NAME" ]; then
  echo "$(timestamp) | COMPOSE_PROJECT_NAME is not defined. Using FILTER for filtering: '$FILTER'."
elif [ -z "$FILTER" ]; then
  echo "$(timestamp) | FILTER is not defined. Using COMPOSE_PROJECT_NAME for filtering: '$COMPOSE_PROJECT_NAME'."
else
  echo "$(timestamp) | Both COMPOSE_PROJECT_NAME and FILTER are defined:"
  echo "$(timestamp) | COMPOSE_PROJECT_NAME='$COMPOSE_PROJECT_NAME', FILTER='$FILTER'."
fi

# Constructing the docker ps command
DOCKER_PS_CMD="docker ps"

# Filter by COMPOSE_PROJECT_NAME (if set)
if [ -n "$COMPOSE_PROJECT_NAME" ]; then
  DOCKER_PS_CMD="$DOCKER_PS_CMD --filter 'label=com.docker.compose.project=$COMPOSE_PROJECT_NAME'"
fi

# Add additional filters from the FILTER variable (if set)
if [ -n "$FILTER" ]; then
  for filter in $FILTER; do
    DOCKER_PS_CMD="$DOCKER_PS_CMD --filter '$filter'"
  done
fi

# Enforce filtering by "cron.enabled=true"
DOCKER_PS_CMD="$DOCKER_PS_CMD --filter 'label=cron.enabled=true'"

# Get filtered containers
containers=$(eval "$DOCKER_PS_CMD -q")

echo "$(timestamp) | Updating cron jobs..."

# Create a new crontab file with a unique name
true > "$CRON_FILE_NEW"

# Process each container
for container in $containers; do
  cron_jobs=$(extract_cron_jobs "$container")
  target_container=$(docker inspect -f '{{.Name}}' "$container" | cut -c2-) # Remove leading /

  if [ -z "$cron_jobs" ]; then
    log "No cron jobs found for container: $target_container ($container)"
  else
    log "Processing container: $target_container ($container)"

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
        cron_entry="$job_schedule docker exec $target_container sh -c '$job_command' 2>&1 | tee -a $CRON_LOG_DIR/\$(date -u +\%Y-\%m-\%d_\%H-\%M-\%S_\%Z)_$job_key.log"

        # Run the supercronic test
        echo "$cron_entry" > "$CRON_FILE_TEST"
        if ! supercronic -test "$CRON_FILE_TEST" > /dev/null 2>&1; then
          echo "$(timestamp) | ========================================================"
          printf "\nERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR\n\n"
          echo "BAD CRON JOB: '$cron_entry'"
          supercronic -debug -test "$CRON_FILE_TEST"
          printf "==================================================================================\n\n"
          # TODO make the cron container unhealthy
        else
          echo "$cron_entry" >> "$CRON_FILE_NEW"
          log "Scheduled task for $target_container: $cron_entry"
        fi
      else
        echo "$(timestamp) | Error: job_schedule or job_command is missing for job $job_key in container $target_container."
      fi
    done
  fi
done

# Check if there are changes
if ! diff -u "$CRON_FILE" "$CRON_FILE_NEW" > /dev/null; then
  # Print the changes in the crontab:
  printf "\n%s | Changes in the crontab file:\n" "$(timestamp)"
  diff -u "$CRON_FILE" "$CRON_FILE_NEW" | tail -n +3 # Remove the first two lines containing file names

  if [ ! -s "$CRON_FILE_NEW" ]; then
    printf "\n%s | NO JOBS IN CRONTAB FILE\n\n" "$(timestamp)"
  else
    # Print the updated crontab file
    printf "\n%s | Updated crontab file:\n=========================================\n" "$(timestamp)"
    cat "$CRON_FILE_NEW"
    printf "=========================================\n\n"
  fi

  # Update the crontab file if it looks good for supercronic (we tested it one by one line above, but to make sure)
  if ! supercronic -test "$CRON_FILE_NEW" > /dev/null 2>&1; then
    echo "$(timestamp) | ########################################################"
    printf "\nERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR\n\n"
    echo "SOMETHING IS WRONG IN THE CRONTAB FILE"
    supercronic -debug -test "$CRON_FILE_NEW"
    echo "ERROR: CHANGES ARE NOT APPLIED."
    echo "CURRENT CRONTAB FILE IS:"
    cat "$CRON_FILE"
    printf "##################################################################################\n\n"
    # TODO make the cron container unhealthy
  else
    # Atomic update using mv to prevent race conditions
    mv "$CRON_FILE_NEW" "$CRON_FILE"
    log "Crontab file updated successfully"
  fi
else
  echo "$(timestamp) | No changes detected in crontab file."
fi
