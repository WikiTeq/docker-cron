#!/bin/bash

# Utility functions for log management

# Find the newest tar.gz archive by date and time in filename
# Usage: find_newest_archive <directory>
# Returns: full path to the newest .tar.gz archive, or empty string if no archives found
find_newest_archive() {
    local folder="$1"
    
    # Validate input
    if [ -z "$folder" ]; then
        echo "" >&2
        return 1
    fi
    
    if [ ! -d "$folder" ]; then
        echo "" >&2
        return 1
    fi
    
    # Build timestamp:file pairs and sort newest->oldest, then take the first entry (newest)
    local newest_archive=""
    shopt -s nullglob
    while IFS= read -r pair; do
        # Take the first entry (newest after reverse sort)
        newest_archive=$(echo "$pair" | cut -d: -f2-)
        break
    done < <(
        for archive_file in "$folder"/*.tar.gz; do
            [ -f "$archive_file" ] || continue
            local basename_archive
            basename_archive=$(basename "$archive_file")
            local name_without_ext="${basename_archive%.tar.gz}"
            local timestamp=""
            if [[ "$name_without_ext" =~ ^([0-9]{4})(_.*)?$ ]]; then
                local year="${BASH_REMATCH[1]}"
                timestamp="${year}0101000000"
            elif [[ "$name_without_ext" =~ ^([0-9]{4})-([0-9]{2})(_.*)?$ ]]; then
                local year="${BASH_REMATCH[1]}"; local month="${BASH_REMATCH[2]}"
                timestamp="${year}${month}01000000"
            elif [[ "$name_without_ext" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})(_.*)?$ ]]; then
                local year="${BASH_REMATCH[1]}"; local month="${BASH_REMATCH[2]}"; local day="${BASH_REMATCH[3]}"
                timestamp="${year}${month}${day}000000"
            elif [[ "$name_without_ext" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})(_.*)?$ ]]; then
                local year="${BASH_REMATCH[1]}"; local month="${BASH_REMATCH[2]}"; local day="${BASH_REMATCH[3]}"; local hour="${BASH_REMATCH[4]}"
                timestamp="${year}${month}${day}${hour}0000"
            elif [[ "$name_without_ext" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})-([0-9]{2})(_.*)?$ ]]; then
                local year="${BASH_REMATCH[1]}"; local month="${BASH_REMATCH[2]}"; local day="${BASH_REMATCH[3]}"; local hour="${BASH_REMATCH[4]}"; local minute="${BASH_REMATCH[5]}"
                timestamp="${year}${month}${day}${hour}${minute}00"
            elif [[ "$name_without_ext" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2})_UTC(_.*)?$ ]]; then
                local year="${BASH_REMATCH[1]}"; local month="${BASH_REMATCH[2]}"; local day="${BASH_REMATCH[3]}"; local hour="${BASH_REMATCH[4]}"; local minute="${BASH_REMATCH[5]}"; local second="${BASH_REMATCH[6]}"
                timestamp="${year}${month}${day}${hour}${minute}${second}"
            fi
            if [ -n "$timestamp" ]; then
                printf '%s:%s\n' "$timestamp" "$archive_file"
            fi
        done | LC_ALL=C sort -r
    )
    shopt -u nullglob
    
    if [ -n "$newest_archive" ]; then
        echo "$newest_archive"
        return 0
    else
        echo ""
        return 1
    fi
}

# Compute end window timestamp based on existing logs and target_count
# Usage: compute_end_window <log_dir> <target_count>
# Echoes: YYYY-MM-DD_HH-MM-SS
compute_end_window() {
    local log_dir="$1"
    local target_count="$2"
    local current_datetime
    current_datetime=$(date -u '+%Y-%m-%d_%H-%M-%S')

    # Stream-optimized: build timestamp:file pairs, sort newest->oldest,
    # skip target_count newest, then take the next timestamp as end_window_ts
    local end_window_ts=""
    local skipped=0
    shopt -s nullglob
    while IFS= read -r pair; do
        if [ -z "$pair" ]; then
            continue
        fi
        if [ "$skipped" -lt "$target_count" ]; then
            skipped=$((skipped + 1))
            continue
        fi
        # First entry after skipping target_count
        end_window_ts=$(echo "$pair" | cut -d: -f1)
        break
    done < <(
        for f in "$log_dir"/*.log; do
            [ -f "$f" ] || continue
            b=$(basename "$f")
            if [[ $b =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2})_UTC_ ]]; then
                printf '%s:%s\n' "${BASH_REMATCH[1]}" "$f"
            fi
        done | LC_ALL=C sort -r
    )
    shopt -u nullglob

    # If there were <= target_count files, fall back to current time
    if [ -z "$end_window_ts" ]; then
        end_window_ts="$current_datetime"
    fi

    # Take minimum of current time and computed window
    local earliest
    earliest=$(printf '%s\n%s' "$current_datetime" "$end_window_ts" | LC_ALL=C sort | head -1)
    if [ "$earliest" = "$current_datetime" ]; then
        echo "$current_datetime"
    else
        echo "$end_window_ts"
    fi
}

# Get timestamp (YYYY-MM-DD_HH-MM-SS) of the oldest uncompressed log file by filename
# Usage: get_oldest_log_timestamp <log_dir>
# Echoes: YYYY-MM-DD_HH-MM-SS on success; empty string on failure; returns 0/1
get_oldest_log_timestamp() {
    local log_dir="$1"
    
    if [ -z "$log_dir" ] || [ ! -d "$log_dir" ]; then
        echo ""
        return 1
    fi
    
    # Build timestamp list and sort oldest->newest, take first
    local ts=""
    shopt -s nullglob
    ts=$(
        for f in "$log_dir"/*.log; do
            [ -f "$f" ] || continue
            local b
            b=$(basename "$f")
            if [[ $b =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2})_UTC_ ]]; then
                printf '%s\n' "${BASH_REMATCH[1]}"
            fi
        done | LC_ALL=C sort | head -1
    )
    shopt -u nullglob
    
    if [ -n "$ts" ]; then
        echo "$ts"
        return 0
    else
        echo ""
        return 1
    fi
}

# Helper function to determine which granularity to lock based on previous period
# Usage: determine_granularity_to_lock <previous_period_key> <year_key> <month_key> <day_key> <hour_key> <minute_key> <second_key>
# Returns: granularity name to lock (year, month, day, hour, minute, second) or empty string
determine_granularity_to_lock() {
    local previous_period="$1"
    local year_key="$2"
    local month_key="$3"
    local day_key="$4"
    local hour_key="$5"
    local minute_key="$6"
    local second_key="$7"
    
    if [ -z "$previous_period" ]; then
        echo ""
        return
    fi
    
    # Determine granularity of previous_period by checking its format
    # Format checks: year (YYYY), month (YYYY-MM), day (YYYY-MM-DD), etc.
    local prev_granularity=""
    
    if [[ "$previous_period" =~ ^[0-9]{4}$ ]]; then
        # Year format: YYYY
        prev_granularity="year"
    elif [[ "$previous_period" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
        # Month format: YYYY-MM
        prev_granularity="month"
    elif [[ "$previous_period" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        # Day format: YYYY-MM-DD
        prev_granularity="day"
    elif [[ "$previous_period" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}$ ]]; then
        # Hour format: YYYY-MM-DD_HH
        prev_granularity="hour"
    elif [[ "$previous_period" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}$ ]]; then
        # Minute format: YYYY-MM-DD_HH-MM
        prev_granularity="minute"
    elif [[ "$previous_period" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
        # Second format: YYYY-MM-DD_HH-MM-SS
        prev_granularity="second"
    else
        # Unknown format
        echo ""
        return
    fi
    
    # Check if previous_period matches the file's period at that granularity
    case "$prev_granularity" in
        "year")
            if [ "$previous_period" = "$year_key" ]; then
                echo "month"
            else
                echo ""
            fi
            ;;
        "month")
            if [ "$previous_period" = "$month_key" ]; then
                echo "day"
            else
                echo ""
            fi
            ;;
        "day")
            if [ "$previous_period" = "$day_key" ]; then
                echo "hour"
            else
                echo ""
            fi
            ;;
        "hour")
            if [ "$previous_period" = "$hour_key" ]; then
                echo "minute"
            else
                echo ""
            fi
            ;;
        "minute")
            if [ "$previous_period" = "$minute_key" ]; then
                echo "second"
            else
                echo ""
            fi
            ;;
        "second")
            # Second is already finest granularity, nothing to lock
            echo ""
            ;;
        *)
            echo ""
            ;;
    esac
}

# Derive granularity_to_lock from a previous period and first file timestamp
# Usage: derive_granularity_to_lock <previous_period> <first_timestamp>
# first_timestamp is YYYY-MM-DD_HH-MM-SS
derive_granularity_to_lock() {
    local previous_period="$1"
    local first_ts="$2"
    if [ -z "$previous_period" ]; then
        # No previous period, default to year lock
        echo "year"
        return 0
    fi
    if [ -z "$first_ts" ]; then
        echo "year"
        return 0
    fi
    
    local year="${first_ts:0:4}"
    local month="${first_ts:0:7}"
    local day="${first_ts:0:10}"
    local hour="${first_ts:0:13}"
    local minute="${first_ts:0:16}"
    local second="${first_ts:0:19}"
    
    # Check from coarsest to finest: find the first matching period
    # Year level: previous_period matches year prefix?
    if [ "${previous_period:0:4}" = "$year" ]; then
        # Check if previous_period is exactly a year
        if [[ "$previous_period" =~ ^[0-9]{4}$ ]]; then
            echo "month"; return 0
        fi
        # Check if previous_period is a month that matches
        if [[ "$previous_period" =~ ^[0-9]{4}-[0-9]{2}$ ]] && [ "$previous_period" = "$month" ]; then
            echo "day"; return 0
        fi
        # Check if previous_period is a day that matches
        if [[ "$previous_period" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [ "$previous_period" = "$day" ]; then
            echo "hour"; return 0
        fi
        # Check if previous_period matches month (even if it's a day)
        if [ "${previous_period:0:7}" = "$month" ]; then
            echo "day"; return 0
        fi
        # If year matches but nothing finer, lock at month
        echo "month"; return 0
    fi
    
    # No match at all: default to year lock
    echo "year"
}

# Return numeric rank for a granularity (higher is coarser)
# Usage: granularity_rank <granularity>
granularity_rank() {
    case "$1" in
        year) echo 6 ;;
        month) echo 5 ;;
        day) echo 4 ;;
        hour) echo 3 ;;
        minute) echo 2 ;;
        second) echo 1 ;;
        *) echo 0 ;;
    esac
}

# Check if timestamp (YYYY-MM-DD_HH-MM-SS) belongs to the given period
# Usage: timestamp_in_period <granularity> <period_key> <timestamp>
# Exit 0 if in period, 1 otherwise
timestamp_in_period() {
    local granularity="$1"
    local period_key="$2"
    local ts="$3"
    case "$granularity" in
        year)   [ "${ts:0:4}" = "$period_key" ] ;;
        month)  [ "${ts:0:7}" = "$period_key" ] ;;
        day)    [ "${ts:0:10}" = "$period_key" ] ;;
        hour)   [ "${ts:0:13}" = "$period_key" ] ;;
        minute) [ "${ts:0:16}" = "$period_key" ] ;;
        second) [ "${ts:0:19}" = "$period_key" ] ;;
        *) return 1 ;;
    esac
}

# Extract task name from a single log filename. Returns empty if none.
# Usage: extract_task_name_from_filename <filepath>
extract_task_name_from_filename() {
    local filepath="$1"
    local base
    base=$(basename -- "$filepath")
    # Match ..._UTC_<task>.log
    local task
    task=$(printf '%s' "$base" | sed -n 's/.*_UTC_\(.*\)\.log$/\1/p')
    printf '%s' "$task"
}

# Given a newline-separated list of files on stdin, emits the common task name
# if all files share the same non-empty task; otherwise emits empty.
# Usage: printf '%s\n' "$files" | common_task_name_from_list
common_task_name_from_list() {
    local common="" line task
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        task=$(extract_task_name_from_filename "$line")
        if [ -z "$common" ]; then
            common="$task"
        else
            if [ "$task" != "$common" ]; then
                common=""
                break
            fi
        fi
    done
    printf '%s' "$common"
}

# Derive previous_period key from an archive base name (without extension).
# Accepts names like:
#   YYYY
#   YYYY-MM
#   YYYY-MM-DD
#   YYYY-MM-DD_HH
#   YYYY-MM-DD_HH-MM
#   YYYY-MM-DD_HH-MM-SS
# With an optional suffix: _<task>
# Usage: parse_previous_period_from_archive_name <archive_name>
parse_previous_period_from_archive_name() {
    local name="$1"
    # Strip optional _<task> suffix
    local core
    core=$(printf '%s' "$name" | sed 's/\(_[^_][^_]*\)$//')
    # Return the core period key as-is (already in desired formats like YYYY, YYYY-MM, ...)
    printf '%s' "$core"
}

# Helper function to update period state
# Usage: update_period_state <current_state> <new_period_key> <log_file> <target_count>
# Returns: updated state in format: period_key:count:locked:f1:f2:...
#         OR "BREAK" if trying to replace a locked period
# locked=1 means period reached target_count and should not be replaced
update_period_state() {
    local current_state="$1"
    local new_period_key="$2"
    local log_file="$3"
    local target_count="$4"
    # Determine if new/current period keys are YEAR-level (YYYY)
    local is_year_new=0
    [[ "$new_period_key" =~ ^[0-9]{4}$ ]] && is_year_new=1
    
    if [ -z "$current_state" ]; then
        local locked=0
        # Always lock YEAR periods regardless of target_count
        if [ "$is_year_new" -eq 1 ] || [ "$target_count" -eq 1 ]; then
            locked=1
        fi
        echo "${new_period_key}:1:${locked}:${log_file}"
    else
        local current_period_key
        current_period_key=$(echo "$current_state" | cut -d: -f1)
        local current_count
        current_count=$(echo "$current_state" | cut -d: -f2)
        local current_locked
        current_locked=$(echo "$current_state" | cut -d: -f3)
        local current_files
        current_files=$(echo "$current_state" | cut -d: -f4-)
        local is_year_current=0
        [[ "$current_period_key" =~ ^[0-9]{4}$ ]] && is_year_current=1
        
        if [ "$current_period_key" = "$new_period_key" ]; then
            # Match - add to existing array
            local new_count=$((current_count + 1))
            local locked=$current_locked
            # Always keep YEAR locked; otherwise lock on target_count
            if [ "$is_year_new" -eq 1 ]; then
                locked=1
            elif [ "$new_count" -ge "$target_count" ]; then
                locked=1
            fi
            echo "${new_period_key}:${new_count}:${locked}:${current_files}:${log_file}"
        else
            # No match - try to replace with new period
            # If current is YEAR, treat as locked unconditionally
            if [ "$current_locked" -eq 1 ] || [ "$is_year_current" -eq 1 ]; then
                # Period is locked, cannot replace
                echo "BREAK"
            else
                # Can replace
                local locked=0
                # Always lock YEAR periods on initialization
                if [ "$is_year_new" -eq 1 ] || [ "$target_count" -eq 1 ]; then
                    locked=1
                fi
                echo "${new_period_key}:1:${locked}:${log_file}"
            fi
        fi
    fi
}

# Group log files by time periods
# Usage: group_logs_by_time <directory> [target_count] [previous_period] [end_window]
# Output format: period_granularity:period_key:file_count:file1:file2:...
# Maintains exactly 6 keys (one per granularity: year, month, day, hour, minute, second)
# When a period reaches target_count, it becomes locked and cannot be replaced
# If previous_period is set, locks the next finer granularity for the first file when periods match
# If end_window is set (YYYY-MM-DD_HH-MM-SS), exits with "BREAK" when reaching end of window
group_logs_by_time() {
    local folder="$1"
    local target_count="${2:-999999}"
    local granularity_to_lock="$3"
    local end_window="$4"
    
    # Validate input
    if [ -z "$folder" ]; then
        echo "" >&2
        return 1
    fi
    
    if [ ! -d "$folder" ]; then
        echo "" >&2
        return 1
    fi
    
    # Build sorted file list using timestamp:file pairs
    shopt -s nullglob
    mapfile -t sorted_files < <(
        for file in "$folder"/*.log; do
            [ -f "$file" ] || continue
            basename_file=$(basename "$file")
            # Extract timestamp: YYYY-MM-DD_HH-MM-SS (first 19 characters before _UTC)
            if [[ "$basename_file" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2})_UTC_ ]]; then
                printf '%s:%s\n' "${BASH_REMATCH[1]}" "$file"
            fi
        done | LC_ALL=C sort | cut -d: -f2-
    )
    shopt -u nullglob
    
    if [ ${#sorted_files[@]} -eq 0 ]; then
        return 1
    fi
    
    # Initialize arrays for each granularity level
    # Each array will hold: period_key,count,locked,files (colon-separated)
    local year_state=""
    local month_state=""
    local day_state=""
    local hour_state=""
    local minute_state=""
    local second_state=""
    local break_granularity=""
    local first_file_processed=false
    
    # Process each log file
    for log_file in "${sorted_files[@]}"; do
        if [ -z "$log_file" ]; then
            continue
        fi
        
        local basename_log
        basename_log=$(basename "$log_file")
        
        # Parse timestamp from filename: YYYY-MM-DD_HH-MM-SS_UTC_task.log
        if [[ "$basename_log" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2})_UTC_(.+)\.log$ ]]; then
            local year="${BASH_REMATCH[1]}"
            local month="${BASH_REMATCH[2]}"
            local day="${BASH_REMATCH[3]}"
            local hour="${BASH_REMATCH[4]}"
            local minute="${BASH_REMATCH[5]}"
            local second="${BASH_REMATCH[6]}"
            
            # Extract all period keys
            local year_key="$year"
            local month_key="${year}-${month}"
            local day_key="${year}-${month}-${day}"
            local hour_key="${year}-${month}-${day}_${hour}"
            local minute_key="${year}-${month}-${day}_${hour}-${minute}"
            local second_key="${year}-${month}-${day}_${hour}-${minute}-${second}"
            
            # For the first file only, apply provided granularity_to_lock (if any)
            local is_first_file=false
            if [ "$first_file_processed" = false ] && [ -n "$granularity_to_lock" ]; then
                is_first_file=true
            fi
            
            # Determine target_count for each granularity for this file
            # If this is first file and granularity_to_lock is set, use target_count=1 for that granularity
            local year_target="$target_count"
            local month_target="$target_count"
            local day_target="$target_count"
            local hour_target="$target_count"
            local minute_target="$target_count"
            local second_target="$target_count"
            
            if [ "$is_first_file" = true ] && [ -n "$granularity_to_lock" ]; then
                case "$granularity_to_lock" in
                    "year") year_target=1 ;;
                    "month") month_target=1 ;;
                    "day") day_target=1 ;;
                    "hour") hour_target=1 ;;
                    "minute") minute_target=1 ;;
                    "second") second_target=1 ;;
                esac
            fi
            
            # Mark first file as processed after setting is_first_file
            first_file_processed=true
            
            # Process each granularity level and check for BREAK (reverse order: finest to coarsest)
            local new_second_state
            new_second_state=$(update_period_state "$second_state" "$second_key" "$log_file" "$second_target")
            if [ "$new_second_state" = "BREAK" ]; then
                break_granularity="second"
                break
            fi
            second_state="$new_second_state"

            local new_minute_state
            new_minute_state=$(update_period_state "$minute_state" "$minute_key" "$log_file" "$minute_target")
            if [ "$new_minute_state" = "BREAK" ]; then
                break_granularity="minute"
                break
            fi
            minute_state="$new_minute_state"

            local new_hour_state
            new_hour_state=$(update_period_state "$hour_state" "$hour_key" "$log_file" "$hour_target")
            if [ "$new_hour_state" = "BREAK" ]; then
                break_granularity="hour"
                break
            fi
            hour_state="$new_hour_state"

            local new_day_state
            new_day_state=$(update_period_state "$day_state" "$day_key" "$log_file" "$day_target")
            if [ "$new_day_state" = "BREAK" ]; then
                break_granularity="day"
                break
            fi
            day_state="$new_day_state"

            local new_month_state
            new_month_state=$(update_period_state "$month_state" "$month_key" "$log_file" "$month_target")
            if [ "$new_month_state" = "BREAK" ]; then
                break_granularity="month"
                break
            fi
            month_state="$new_month_state"

            local new_year_state
            new_year_state=$(update_period_state "$year_state" "$year_key" "$log_file" "$year_target")
            if [ "$new_year_state" = "BREAK" ]; then
                break_granularity="year"
                break
            fi
            year_state="$new_year_state"
            
            # Check if we've reached the end of the time window
            if [ -n "$end_window" ]; then
                # Extract timestamp from current file for comparison
                local file_timestamp="${year}-${month}-${day}_${hour}-${minute}-${second}"
                
                # Compare timestamps (YYYY-MM-DD_HH-MM-SS format sorts correctly)
                # Use sort for portable comparison that works in all shells
                # If file_timestamp >= end_window, the sorted first line will be end_window or they're equal
                local earliest
                earliest=$(printf "%s\n%s" "$file_timestamp" "$end_window" | sort | head -1)
                if [ "$earliest" != "$file_timestamp" ] || [ "$file_timestamp" = "$end_window" ]; then
                    echo "BREAK"
                    return 0
                fi
            fi
        fi
    done
    
    # If a granularity reached BREAK, output only that granularity
    if [ -n "$break_granularity" ]; then
        local granularities=("year" "month" "day" "hour" "minute" "second")
        local states=("$year_state" "$month_state" "$day_state" "$hour_state" "$minute_state" "$second_state")
        
        for i in "${!granularities[@]}"; do
            local granularity="${granularities[$i]}"
            if [ "$granularity" = "$break_granularity" ]; then
                local state="${states[$i]}"
                # Parse and output the state for this granularity
                local period_key
                period_key=$(echo "$state" | cut -d: -f1)
                local count
                count=$(echo "$state" | cut -d: -f2)
                local files
                files=$(echo "$state" | cut -d: -f4-)
                # Output header line: granularity:period_key:count
                echo "${granularity}:${period_key}:${count}"
                # Output each file on a separate line
                if [ -n "$files" ]; then
                    echo "$files" | tr ':' '\n'
                fi
                return 0
            fi
        done
    fi
    
    # Otherwise, this path should be unreachable
    echo "ERROR: Unexpected state in group_logs_by_time: no BREAK granularity and no targeted output." >&2
    return 1
}
