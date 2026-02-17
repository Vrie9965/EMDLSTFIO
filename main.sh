#!/bin/bash

# ############# #
# Author: EBTRFIO
# Date: Dec. 10 2022
# Licence: None
# Version: v1.6.0
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

# Check if the frame was already posted
if [[ -e "${FRMENV_LOG_FILE}" ]] && grep -qE "\[√\] Frame: ${prev_frame}, Episode ${episode}" "${FRMENV_LOG_FILE}"; then
	next_frame="$((prev_frame+=1))"
	printf '%s' "${next_frame}" > ./fb/frameiterator
	exit 0
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

# post it in the front page
post_response="$(post_fp "${prev_frame}" 2>&1)" || {
	printf '%s\n' "[ERROR] post_fp failed for frame ${prev_frame}: ${post_response}" >> "${FRMENV_LOG_FILE}"
	helper_statfailed "${prev_frame}" "${episode}" 1
}
post_id="$(jq -r '.post_id // .id // empty' <<< "${post_response}" 2>/dev/null)"
[[ -n "${post_id}" ]] || post_id="$(grep -Po '(?=[0-9])(.*)(?=\",\")' <<< "${post_response}" | head -n1)"
[[ -n "${post_id}" ]] || { printf '%s\n' "[ERROR] Empty post_id response for frame ${prev_frame}" >> "${FRMENV_LOG_FILE}" ; helper_statfailed "${prev_frame}" "${episode}" 1 ;}
unset post_response

if [[ "${sub_posting}" = "1" ]]; then
	post_commentsubs "${prev_frame}" "${post_id}" || helper_statfailed "${prev_frame}" "${episode}" 1
fi

# Post images in Albums
[[ -z "${album}" ]] || post_album "${prev_frame}" || helper_statfailed "${prev_frame}" "${episode}" 1

# Addons, Random Crop from frame
if [[ "${rand_post}" = "1" ]]; then
	sleep "${delay_action}" # Delay
	post_randomcrop "${prev_frame}" "${post_id}" || helper_statfailed "${prev_frame}" "${episode}" 1
fi

# Addons, GIF posting
if [[ "${gif_post}" = "1" ]]; then
	sleep "${delay_action}" # Delay
	if [[ -n "${FRMENV_GIFTOKEN}" ]] && [[ "${prev_frame}" -gt "${gif_prev_framecount}" ]]; then
		post_gif "$((prev_frame - gif_prev_framecount))" "${prev_frame}" "${post_id}" || helper_statfailed "${prev_frame}" "${episode}" 1
	fi
fi

# This will note that the Post was success, without errors and append it to log file
log_entry="[√] Frame: ${prev_frame}, Episode ${episode} https://facebook.com/${post_id}"
[[ -n "${log_entry//[[:space:]]/}" ]] || helper_statfailed "${prev_frame}" "${episode}" 1
printf '%s\n' "${log_entry}" >> "${FRMENV_LOG_FILE}" || helper_statfailed "${prev_frame}" "${episode}" 1
unset log_entry

# Lastly, This will increment prev_frame variable and redirect it to file
next_frame="$((prev_frame+=1))"
incmnt_cnt="$(($(<./counter_total_frames.txt)+1))"
printf '%s' "${next_frame}" > "${FRMENV_ITER_FILE}"
printf '%s' "${incmnt_cnt}" > ./counter_total_frames.txt

# Note:
# Please test it with development mode ON first before going to publish it, Publicly or (live mode)
# And i recommend using crontab as your scheduler
