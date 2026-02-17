#!/bin/bash
#
# check if all req. was provided in your repository for preparing frames to avoid errors

# import config
. config.conf
. secret.sh

FRMENV_FBTOKEN="${1:-${FRMENV_FBTOKEN}}"
FRMENV_GIFTOKEN="${2:-${FRMENV_GIFTOKEN}}"

format_noerr(){ printf '$\\fbox{\\color{#126329}\\textsf{\\normalsize  &#x2611; \\kern{0.2cm}\\small  %s  }}$' "${*}" ;}
format_err(){ printf '$\\fbox{\\color{#82061E}\\textsf{\\normalsize  &#x26A0; \\kern{0.2cm}\\small  %s  }}$' "${*}" ;} 
format_table(){ printf '| \x60%s\x60 | %s |\n' "${1}" "${2}" ;}

# Append Header
printf '<h1 align="center">%s</h1>\n<p align="center">%s</p>\n<div align="center">\n' "Repo Check" "This is where you can check whether it's all prepared or not"
printf '\n\n| %s | %s |\n| ---- | ---- |\n' "Variable/Object" "State"

checkif(){
	for i; do
		if [[ -z "${!i}" ]]; then
			format_table "${i}" "$(format_err "Variable is empty")" && err_state="1"
			printf '\e[31mERROR\e[0m - %s\n' "Variable is empty" >&2
		else
			format_table "${i}" "$(format_noerr "Passed")"
		fi
	done
}

sub_check(){
	if [[ "${sub_posting}" = "1" ]]; then
		if [[ -z "${FRMENV_COMMENTSUBS_LOCATION}" ]]; then
			format_table "FRMENV_COMMENTSUBS_LOCATION" "$(format_err "Variable is empty")" && err_state="1"
			printf '\e[31mERROR\e[0m - %s\n' "Variable is empty" >&2
		elif [[ ! -d "${FRMENV_COMMENTSUBS_LOCATION}" ]]; then
			format_table "commentsubs" "$(format_err "Directory not found")" && err_state="1"
			printf '\e[31mERROR\e[0m - %s\n' "Directory not found" >&2
		elif ! compgen -G "${FRMENV_COMMENTSUBS_LOCATION}/frame_*.jpg" > /dev/null; then
			format_table "commentsubs" "$(format_err "No commentsub images found")" && err_state="1"
			printf '\e[31mERROR\e[0m - %s\n' "No commentsub images found" >&2
		else
			format_table "commentsubs" "$(format_noerr "Passed")"
		fi
	fi
}

frames_check(){
	frame_number="$(find frames/frame_* 2>/dev/null | wc -l)"
	if [[ ! -d frames ]]; then
		format_table "frames" "$(format_err "Frames directory not found")" && err_state="1"
		printf '\e[31mERROR\e[0m - %s\n' "Frames directory not found" >&2
	elif [[ "${frame_number}" -lt 1 ]]; then
		format_table "frames" "$(format_err "No frames available")" && err_state="1"
		printf '\e[31mERROR\e[0m - %s\n' "No frames available" >&2
	else
		format_table "frames" "$(format_noerr "Total Frames: ${frame_number}")"
	fi
	if ! [[ -e fb/frameiterator ]]; then
		format_table "frameiterator" "$(format_err "File not found")" && err_state="1"
		printf '\e[31mERROR\e[0m - %s\n' "File not found" >&2
	elif grep -vEq '^[0-9]*$' fb/frameiterator; then
		format_table "frameiterator" "$(format_err "Invalid format")" && err_state="1"
		printf '\e[31mERROR\e[0m - %s\n' "Invalid format" >&2
	else
		format_table "frameiterator" "$(format_noerr "Valid format")"
		current_iter="$(<fb/frameiterator)"
		current_frame_path="frames/frame_${current_iter}.jpg"
		if [[ ! -s "${current_frame_path}" ]]; then
			format_table "current_frame_file" "$(format_err "Missing frame_${current_iter}.jpg")" && err_state="1"
			printf '\e[31mERROR\e[0m - %s\n' "Missing or empty ${current_frame_path}" >&2
		else
			format_table "current_frame_file" "$(format_noerr "Found frame_${current_iter}.jpg")"
		fi
		unset current_iter current_frame_path
	fi
}

token_check(){
	if [[ -z "${1}" ]]; then
		format_table "fb_token" "$(format_err "Token is empty")" && err_state="1"
		printf '\e[31mERROR\e[0m - %s\n' "Facebook token is empty" >&2
	else
		fb_response="$(curl -sS -w $'\n%{http_code}' "${FRMENV_API_ORIGIN}/me?fields=id,name&access_token=${1}")" || true
		fb_body="$(sed '$d' <<< "${fb_response}")"
		fb_status="$(tail -n1 <<< "${fb_response}")"
		fb_name="$(jq -r '.name // empty' <<< "${fb_body}" 2>/dev/null)"
		fb_err_msg="$(jq -r '.error.message // empty' <<< "${fb_body}" 2>/dev/null)"
		fb_err_code="$(jq -r '.error.code // empty' <<< "${fb_body}" 2>/dev/null)"

		if [[ "${fb_status}" != "200" ]]; then
			TEMP_ERR_REASON="Request failed (HTTP ${fb_status:-unknown})"
			[[ -n "${fb_err_code}" ]] && TEMP_ERR_REASON+=" [code ${fb_err_code}]"
			[[ -n "${fb_err_msg}" ]] && TEMP_ERR_REASON+=": ${fb_err_msg}"
			format_table "fb_token" "$(format_err "${TEMP_ERR_REASON}")" && err_state="1"
			printf '\e[31mERROR\e[0m - %s\n' "${TEMP_ERR_REASON}" >&2
		elif [[ -n "${page_name}" ]] && [[ "${fb_name}" != "${page_name}" ]]; then
			TEMP_ERR_REASON="Token page mismatch (expected: ${page_name}, got: ${fb_name:-unknown})"
			format_table "fb_token" "$(format_err "${TEMP_ERR_REASON}")" && err_state="1"
			printf '\e[31mERROR\e[0m - %s\n' "${TEMP_ERR_REASON}" >&2
		else
			format_table "fb_token" "$(format_noerr "Token is Working")"
			fb_photo_probe="$(curl -sS -w $'\n%{http_code}' "${FRMENV_API_ORIGIN}/me/photos?limit=1&access_token=${1}")" || true
			fb_photo_body="$(sed '$d' <<< "${fb_photo_probe}")"
			fb_photo_status="$(tail -n1 <<< "${fb_photo_probe}")"
			fb_photo_err_msg="$(jq -r '.error.message // empty' <<< "${fb_photo_body}" 2>/dev/null)"
			fb_photo_err_code="$(jq -r '.error.code // empty' <<< "${fb_photo_body}" 2>/dev/null)"
			if [[ "${fb_photo_status}" != "200" ]]; then
				TEMP_PHOTO_ERR="No photo endpoint access (HTTP ${fb_photo_status:-unknown})"
				[[ -n "${fb_photo_err_code}" ]] && TEMP_PHOTO_ERR+=" [code ${fb_photo_err_code}]"
				[[ -n "${fb_photo_err_msg}" ]] && TEMP_PHOTO_ERR+=": ${fb_photo_err_msg}"
				format_table "fb_photo_access" "$(format_err "${TEMP_PHOTO_ERR}")" && err_state="1"
				printf '\e[31mERROR\e[0m - %s\n' "${TEMP_PHOTO_ERR}" >&2
			else
				format_table "fb_photo_access" "$(format_noerr "Passed")"
			fi
			unset fb_photo_probe fb_photo_body fb_photo_status fb_photo_err_msg fb_photo_err_code TEMP_PHOTO_ERR
		fi
		unset fb_response fb_body fb_status fb_name fb_err_msg fb_err_code TEMP_ERR_REASON
	fi

	if [[ "${gif_post}" = "1" ]]; then
		if [[ -z "${2}" ]]; then
			format_table "gif_token" "$(format_err "Token is empty")" && err_state="1"
			printf '\e[31mERROR\e[0m - %s\n' "Giphy token is empty" >&2
		else
			gif_status="$(curl -sS -o /dev/null -w '%{http_code}' "https://api.giphy.com/v1/gifs/trending?api_key=${2}")"
			if [[ "${gif_status}" = "200" ]]; then
				format_table "gif_token" "$(format_noerr "Token is Working")"
			else
				TEMP_GIF_ERR="Request failed (HTTP ${gif_status:-unknown})"
				format_table "gif_token" "$(format_err "${TEMP_GIF_ERR}")" && err_state="1"
				printf '\e[31mERROR\e[0m - %s\n' "${TEMP_GIF_ERR}" >&2
			fi
			unset gif_status TEMP_GIF_ERR
		fi
	fi
}

checkif name season episode total_frame fph mins delay_action
sub_check
frames_check
token_check "${FRMENV_FBTOKEN}" "${FRMENV_GIFTOKEN}"
printf '\n</div>'
[[ "${err_state}" != "1" ]] || exit 1
: "success"
