#!/bin/bash
# */
# This is where all the actions will happen
# /*

post_gif(){
	TEMP_GIFURL="$(process_creategif "${1}" "${2}")"
	TEMP_CRAFTMESSAGE="GIF created from last ${gif_prev_framecount} frames (${1}-${2})"
	curl -sfLX POST \
		-d "message=${TEMP_CRAFTMESSAGE}" \
		-d "attachment_share_url=${TEMP_GIFURL}" \
		-o /dev/null \
	"${FRMENV_API_ORIGIN}/${FRMENV_FBAPI_VER}/${3}/comments?access_token=${FRMENV_FBTOKEN}" || return 1
	unset TEMP_CRAFTMESSAGE
}

post_randomcrop(){
	TEMP_CRAFTMESSAGE="$(process_randomcrop "${FRMENV_FRAME_LOCATION}/frame_${1}.jpg")"
	curl -sfLX POST \
		--retry 2 \
		--retry-connrefused \
		--retry-delay 7 \
		-F "message=${TEMP_CRAFTMESSAGE}" \
		-F "source=@${FRMENV_RC_LOCATION}" \
		-o /dev/null \
	"${FRMENV_API_ORIGIN}/${FRMENV_FBAPI_VER}/${2}/comments?access_token=${FRMENV_FBTOKEN}" || return 1
	unset TEMP_CRAFTMESSAGE
}

post_fp(){
	local endpoint response response_body response_status
	local fb_err_type fb_err_code fb_err_msg
	endpoint="${FRMENV_API_ORIGIN}/me/photos?access_token=${FRMENV_FBTOKEN}&published=1"
	response="$(
		curl -sSLX POST \
			--retry 2 \
			--retry-connrefused \
			--retry-delay 7 \
			-F "message=${message}" \
			-F "source=@${FRMENV_FRAME_LOCATION}/frame_${1}.jpg" \
			-w $'\n%{http_code}' \
		"${endpoint}"
	)" || {
		printf '%s\n' "[ERROR] Network failure while posting frame ${1} to ${endpoint}" >&2
		return 1
	}
	response_body="$(sed '$d' <<< "${response}")"
	response_status="$(tail -n1 <<< "${response}")"
	if [[ "${response_status}" != "200" ]]; then
		fb_err_type="$(jq -r '.error.type // empty' <<< "${response_body}" 2>/dev/null)"
		fb_err_code="$(jq -r '.error.code // empty' <<< "${response_body}" 2>/dev/null)"
		fb_err_msg="$(jq -r '.error.message // empty' <<< "${response_body}" 2>/dev/null)"
		printf '%s\n' "[ERROR] post_fp HTTP ${response_status:-unknown} type=${fb_err_type:-unknown} code=${fb_err_code:-unknown} message=${fb_err_msg:-unknown}" >&2
		[[ -n "${response_body}" ]] && printf '%s\n' "[ERROR] post_fp body: ${response_body}" >&2
		return 1
	fi
	printf '%s\n' "${response_body}"
	unset endpoint response response_body response_status fb_err_type fb_err_code fb_err_msg
}

post_commentsubs(){
	local commentsub_path="${FRMENV_COMMENTSUBS_LOCATION}/frame_${1}.jpg"
	if [[ -f "${commentsub_path}" ]]; then
		curl -sfLX POST \
			--retry 2 \
			--retry-connrefused \
			--retry-delay 7 \
			-F "source=@${commentsub_path}" \
			-o /dev/null \
		"${FRMENV_API_ORIGIN}/${FRMENV_FBAPI_VER}/${2}/comments?access_token=${FRMENV_FBTOKEN}" || return 1
		return 0
	fi
	# Missing commentsub image is not an error; skip silently.
	return 0
}

post_album(){
	curl -sfLX POST \
		--retry 2 \
		--retry-connrefused \
		--retry-delay 7 \
		-F "source=@${FRMENV_FRAME_LOCATION}/frame_${1}.jpg" \
		-F "message=${message}" \
		-o /dev/null \
	"${FRMENV_API_ORIGIN}/${album}/photos?access_token=${FRMENV_FBTOKEN}&published=1" || return 1
}

post_changedesc(){
	ovr_all="$(sed -E ':L;s=\b([0-9]+)([0-9]{3})\b=\1,\2=g;t L' counter_total_frames.txt)"
	get_interval="$(sed -nE 's|.*posting_interval="([0-9]+)".*|\1|p' ./config.conf)"
	TEMP_ABT_TXT="$(eval "printf '%s' \"$(sed -E 's_\{\\n\}_\n_g;s_\{([^\x7d]*)\}_\${\1:-??}_g;s|ovr_all:-\?\?|ovr_all:-0|g' <<< "${abt_txt}"\")")"
	curl -sLk -X POST "${FRMENV_API_ORIGIN}/me/?access_token=${1}" --data-urlencode "about=${TEMP_ABT_TXT}" -o /dev/null || true
	unset TEMP_ABT_TXT 
}
