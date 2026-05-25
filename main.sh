#!/bin/bash

# ############# #
# Author: EBTRFIO
# Date: Dec. 10 2022
# Licence: None
# Version: v1.7.0
# ############# #

# --- Dependencies --- #
# * bash
# * imgmagick (optional if GIF posting and Random Crop were enabled)
# * gnu sed
# * grep
# * curl
# * bc
# ############# #

# Initialize variable
: "${season:=}"
: "${episode:=}"
: "${total_frame:=}"
: "${img_fps:=}"

# Booleans Variables (Don't Modify if you don't know what you're doing)
: "${rand_post:=0}"
: "${gif_post:=0}"

# Sub-action retry settings
: "${SUB_ACTION_RETRIES:=3}"
: "${SUB_ACTION_RETRY_DELAY:=10}"

# Import needed scripts
. secret.sh
. config.conf
. scripts/helpers.sh
. scripts/process.sh
. scripts/post.sh

# These token variables are required when making request and auths in APIs
# Create secret.sh file to assign the token variable
# (e.g)
# FRMENV_FBTOKEN="{your_api_key}"
# FRMENV_GIFTOKEN="{your_api_key}"
#
# ###################### #
# or Supply Arguments in Github Workflows
# you must create your Environment Variables in Secrets
FRMENV_FBTOKEN="${1:-${FRMENV_FBTOKEN}}"
FRMENV_GIFTOKEN="${2:-${FRMENV_GIFTOKEN}}"

# Check all the dependencies if installed
helper_depcheck awk sed grep curl bc jq || helper_statfailed 1

# Create DIRs and files for iterator and temps/logs
[[ -d ./fb ]] || mkdir ./fb
[[ -e "${FRMENV_ITER_FILE}" ]] || printf '%s' "1" > "${FRMENV_ITER_FILE}"
{ [[ -z "$(<"${FRMENV_ITER_FILE}")" ]] || [[ "$(<"${FRMENV_ITER_FILE}")" -lt 1 ]] ;} && printf '%s' "1" > "${FRMENV_ITER_FILE}"

[[ "${total_frame}" -lt "$(<"${FRMENV_ITER_FILE}")" ]] && exit 12

# Get the previous frame from a file that acts like an iterator
prev_frame="$(<"${FRMENV_ITER_FILE}")"

# Check if the frame was already posted (fully or partially)
# [√] = fully posted, [~] = partially posted (main post done, sub-actions pending), [!] = posted with sub-action warnings
existing_post_id=""
if [[ -e "${FRMENV_LOG_FILE}" ]]; then
        if grep -qE "\[√\] Frame: ${prev_frame}, Episode ${episode}" "${FRMENV_LOG_FILE}"; then
                # Frame fully posted, skip entirely
                next_frame="$((prev_frame+=1))"
                printf '%s' "${next_frame}" > ./fb/frameiterator
                exit 0
        fi
        # Check for partial entries [~] or [!] — the main Facebook post exists, we should not re-post it
        existing_post_id="$(grep -oE "\[[~!]\] Frame: ${prev_frame}, Episode ${episode} https://facebook.com/[^[:space:]]+" "${FRMENV_LOG_FILE}" | grep -oE 'https://facebook.com/[0-9_]+' | head -n1 | sed 's|https://facebook.com/||')"
fi

# Check if the variables are filled up
helper_varchecker 'lack of basic information (message variable)' "${season}" "${episode}" "${total_frame}"

# get time-stamps
if [[ -n "${img_fps}" ]]; then
        frame_timestamp="$(process_sectotime "${prev_frame}" "timestamp")"
fi

# Refer to config.conf
message="$(eval "printf '%s' \"$(sed -E 's_\{\\n\}_\n_g;s_(\{[^\x7d]*\})_\$\1_g' <<< "${message}"\")")"

# Verify frame file exists before sending request.
frame_path="${FRMENV_FRAME_LOCATION}/frame_${prev_frame}.jpg"
if [[ ! -s "${frame_path}" ]]; then
        printf '%s\n' "[ERROR] Missing frame image: ${frame_path}" >> "${FRMENV_LOG_FILE}"
        helper_statfailed "${prev_frame}" "${episode}" 1
fi

# Helper: retry a sub-action with backoff
# Usage: retry_sub_action "description" function_name [args...]
retry_sub_action() {
        local desc="${1}"
        shift
        local attempt=1
        while [[ "${attempt}" -le "${SUB_ACTION_RETRIES}" ]]; do
                if "$@"; then
                        return 0
                fi
                if [[ "${attempt}" -lt "${SUB_ACTION_RETRIES}" ]]; then
                        local wait_time="$(( SUB_ACTION_RETRY_DELAY * attempt ))"
                        printf '%s\n' "[WARN] ${desc} failed (attempt ${attempt}/${SUB_ACTION_RETRIES}), retrying in ${wait_time}s..." >&2
                        sleep "${wait_time}"
                fi
                attempt="$((attempt + 1))"
        done
        printf '%s\n' "[ERROR] ${desc} failed after ${SUB_ACTION_RETRIES} attempts" >&2
        return 1
}

# Post to the front page (CRITICAL - this is the main post, must succeed)
if [[ -n "${existing_post_id}" ]]; then
        # Main post already exists from a previous partial run, skip it
        post_id="${existing_post_id}"
        printf '%s\n' "[INFO] Frame ${prev_frame}: main post already exists (post_id=${post_id}), skipping post_fp" >&2
else
        post_response="$(post_fp "${prev_frame}" 2>&1)" || {
                printf '%s\n' "[ERROR] post_fp failed for frame ${prev_frame}: ${post_response}" >> "${FRMENV_LOG_FILE}"
                [[ -n "${post_response}" ]] && printf '%s\n' "${post_response}" >&2
                helper_statfailed "${prev_frame}" "${episode}" 1
        }
        post_id="$(jq -r '.post_id // .id // empty' <<< "${post_response}" 2>/dev/null)"
        [[ -n "${post_id}" ]] || post_id="$(grep -Po '(?=[0-9])(.*)(?=\",\")' <<< "${post_response}" | head -n1)"
        [[ -n "${post_id}" ]] || { printf '%s\n' "[ERROR] Empty post_id response for frame ${prev_frame}" >> "${FRMENV_LOG_FILE}" ; helper_statfailed "${prev_frame}" "${episode}" 1 ;}
        unset post_response

        # Record the post_id immediately as a "partial success" entry [~]
        # This gets overwritten by [√] if everything succeeds, but protects against
        # sub-action failures causing duplicate posts on the next run
        partial_entry="[~] Frame: ${prev_frame}, Episode ${episode} https://facebook.com/${post_id}"
        # Remove any existing partial entry for this frame first
        if [[ -e "${FRMENV_LOG_FILE}" ]]; then
                grep -vE "\[~\] Frame: ${prev_frame}, Episode ${episode}" "${FRMENV_LOG_FILE}" > "${FRMENV_LOG_FILE}.tmp" && mv "${FRMENV_LOG_FILE}.tmp" "${FRMENV_LOG_FILE}"
        fi
        printf '%s\n' "${partial_entry}" >> "${FRMENV_LOG_FILE}"
        unset partial_entry
fi

# Sub-actions: these are NON-FATAL. If they fail after retries, we log a warning
# but still count the frame as posted (the main post already exists on Facebook).

sub_action_errors=0

if [[ "${sub_posting}" = "1" ]]; then
        if ! retry_sub_action "post_commentsubs (frame ${prev_frame})" post_commentsubs "${prev_frame}" "${post_id}"; then
                sub_action_errors="$((sub_action_errors + 1))"
        fi
fi

# Post images in Albums
if [[ -n "${album}" ]]; then
        if ! retry_sub_action "post_album (frame ${prev_frame})" post_album "${prev_frame}"; then
                sub_action_errors="$((sub_action_errors + 1))"
        fi
fi

# Addons, Random Crop from frame
if [[ "${rand_post}" = "1" ]]; then
        sleep "${delay_action}" # Delay
        if ! retry_sub_action "post_randomcrop (frame ${prev_frame})" post_randomcrop "${prev_frame}" "${post_id}"; then
                sub_action_errors="$((sub_action_errors + 1))"
        fi
fi

# Addons, GIF posting
if [[ "${gif_post}" = "1" ]]; then
        sleep "${delay_action}" # Delay
        if [[ -n "${FRMENV_GIFTOKEN}" ]] && [[ "${prev_frame}" -gt "${gif_prev_framecount}" ]]; then
                if ! retry_sub_action "post_gif (frame ${prev_frame})" post_gif "$((prev_frame - gif_prev_framecount))" "${prev_frame}" "${post_id}"; then
                        sub_action_errors="$((sub_action_errors + 1))"
                fi
        fi
fi

# Record the final status in the log
if [[ "${sub_action_errors}" -eq 0 ]]; then
        # Full success - replace [~] partial entry with [√] confirmed entry
        if [[ -e "${FRMENV_LOG_FILE}" ]]; then
                sed -i "s|\[~\] Frame: ${prev_frame}, Episode ${episode} https://facebook.com/${post_id}|[√] Frame: ${prev_frame}, Episode ${episode} https://facebook.com/${post_id}|" "${FRMENV_LOG_FILE}"
        fi
else
        # Partial success - upgrade [~] to [!] to indicate main post succeeded with sub-action warnings
        if [[ -e "${FRMENV_LOG_FILE}" ]]; then
                sed -i "s|\[~\] Frame: ${prev_frame}, Episode ${episode} https://facebook.com/${post_id}|[!] Frame: ${prev_frame}, Episode ${episode} https://facebook.com/${post_id}|" "${FRMENV_LOG_FILE}"
        fi
        printf '%s\n' "[WARN] Frame ${prev_frame}: main post succeeded but ${sub_action_errors} sub-action(s) failed" >&2
fi

# Always increment the iterator and counter — the main post exists on Facebook,
# so we must not re-post this frame on the next run
next_frame="$((prev_frame+=1))"
incmnt_cnt="$(($(<./counter_total_frames.txt)+1))"
printf '%s' "${next_frame}" > "${FRMENV_ITER_FILE}"
printf '%s' "${incmnt_cnt}" > ./counter_total_frames.txt

# Note:
# Please test it with development mode ON first before going to publish it, Publicly or (live mode)
# And i recommend using crontab as your scheduler
