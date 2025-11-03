#!/bin/bash

# Log archiving script
# Usage: archive-cron-logs [target_count]
# Default target_count: 20

# Source functions library
# Functions file should be in the same directory as this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCTIONS_FILE="${SCRIPT_DIR}/archive-cron-logs-functions.sh"

# Fallback to absolute path
if [ ! -f "$FUNCTIONS_FILE" ]; then
    FUNCTIONS_FILE="/usr/local/bin/archive-cron-logs-functions.sh"
fi

if [ -f "$FUNCTIONS_FILE" ]; then
    # shellcheck disable=SC1090
    source "$FUNCTIONS_FILE"
else
    echo "Error: Could not find archive-cron-logs-functions.sh" >&2
    exit 1
fi

# Configuration
TARGET_COUNT="${1:-20}"
CRON_LOG_DIR="${CRON_LOG_DIR:-/var/log/cron}"

# Validate target_count is a number
if ! [[ "$TARGET_COUNT" =~ ^[0-9]+$ ]]; then
    echo "Error: target_count must be a positive integer" >&2
    exit 1
fi

# Validate log directory exists
if [ ! -d "$CRON_LOG_DIR" ]; then
    echo "Error: Log directory '$CRON_LOG_DIR' does not exist" >&2
    exit 1
fi

# Get previous_period from newest archive (most recently created)
previous_period=""
newest_archive=$(find_newest_archive "$CRON_LOG_DIR")
if [ -n "$newest_archive" ]; then
    archive_basename=$(basename "$newest_archive" .tar.gz)
    previous_period=$(parse_previous_period_from_archive_name "$archive_basename")
fi

# Calculate end_window via helper function
end_window=$(compute_end_window "$CRON_LOG_DIR" "$TARGET_COUNT")

# Loop: archive groups until we hit end of window (BREAK)
while :; do
    # Recompute first timestamp and granularity_to_lock each iteration
    first_timestamp=$(get_oldest_log_timestamp "$CRON_LOG_DIR")
    granularity_to_lock=$(derive_granularity_to_lock "$previous_period" "$first_timestamp")
    echo "Calling group_logs_by_time with:"
    echo "  directory: $CRON_LOG_DIR"
    echo "  target_count: $TARGET_COUNT"
    echo "  previous_period: ${previous_period:-<none>}"
    echo "  first_timestamp: ${first_timestamp:-<none>}"
    echo "  granularity_to_lock: ${granularity_to_lock:-<none>}"
    echo "  end_window: $end_window"
    echo ""

    result=$(group_logs_by_time "$CRON_LOG_DIR" "$TARGET_COUNT" "$granularity_to_lock" "$end_window")

    if [ "$result" = "BREAK" ]; then
        echo "BREAK: Reached end of time window without collecting enough files"
        break
    fi

    first_line=$(printf '%s\n' "$result" | sed -n '1p')
    if [ -n "$first_line" ]; then
        first_granularity=$(echo "$first_line" | cut -d: -f1)
        first_period_key=$(echo "$first_line" | cut -d: -f2)
        if ! timestamp_in_period "$first_granularity" "$first_period_key" "$first_timestamp"; then
            if [ -z "$granularity_to_lock" ] || [ "$(granularity_rank "$granularity_to_lock")" -gt "$(granularity_rank "$first_granularity")" ]; then
                echo "Re-running with granularity_to_lock=$first_granularity because first_timestamp is outside [$first_period_key]" >&2
                granularity_to_lock="$first_granularity"
                result=$(group_logs_by_time "$CRON_LOG_DIR" "$TARGET_COUNT" "$granularity_to_lock" "$end_window")
                if [ "$result" = "BREAK" ]; then
                    echo "BREAK: Reached end of time window without collecting enough files"
                    break
                fi
            else
                echo "Error: first_timestamp does not belong to [$first_period_key] and cannot coarsen lock (current: $granularity_to_lock, needed: $first_granularity)" >&2
                exit 1
            fi
        fi
    fi

    echo "Result from group_logs_by_time:"
    if [ -n "$result" ]; then
        header_line=$(printf '%s\n' "$result" | sed -n '1p')
        if [ -n "$header_line" ]; then
            granularity=$(echo "$header_line" | cut -d: -f1)
            period_key=$(echo "$header_line" | cut -d: -f2)
            count=$(echo "$header_line" | cut -d: -f3)

            echo "  $granularity [$period_key]: $count file(s)"
            files_block=$(printf '%s\n' "$result" | sed -n '2,$p')
            if [ -n "$files_block" ]; then
                printf '%s\n' "$files_block" | sed 's/^/    /'
            fi

            if [ -n "$files_block" ]; then
                common_task=$(printf '%s\n' "$files_block" | common_task_name_from_list)
                archive_name="${period_key}"
                if [ -n "$common_task" ]; then
                    archive_name="${archive_name}_${common_task}"
                fi
                archive_path="$CRON_LOG_DIR/${archive_name}.tar.gz"

                rel_files=()
                while IFS= read -r f; do
                    [ -z "$f" ] && continue
                    case "$f" in
                        "$CRON_LOG_DIR"/*) rel_files+=("${f#"$CRON_LOG_DIR/"}") ;;
                        *) rel_files+=("$(basename -- "$f")") ;;
                    esac
                done <<EOF
$files_block
EOF

                if [ "${#rel_files[@]}" -gt 0 ]; then
                    echo "Creating archive: $archive_path"
                    tar -C "$CRON_LOG_DIR" -czf "$archive_path" "${rel_files[@]}"
                    tar_status=$?
                    if [ $tar_status -ne 0 ]; then
                        echo "Error: tar failed with status $tar_status" >&2
                        exit $tar_status
                    fi
                    removed_count=0
                    while IFS= read -r f; do
                        [ -z "$f" ] && continue
                        if rm -f -- "$f"; then
                            removed_count=$((removed_count+1))
                        fi
                    done <<EOF
$files_block
EOF
                    echo "Archived and removed $removed_count file(s)."
                    sleep 1
                    # Update previous_period from the archive name for the next iteration
                    previous_period=$(parse_previous_period_from_archive_name "$archive_name")
                else
                    echo "No files to archive." >&2
                fi
            fi
        fi
    fi
done

exit 0
