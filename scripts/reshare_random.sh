#!/bin/bash
# File: EOFIO12/scripts/reshare_random.sh
: "${FRMENV_FBTOKEN:=${TOK_FB:-}}"
if [[ -z "$FRMENV_FBTOKEN" ]]; then
  echo "ERROR: FRMENV_FBTOKEN is empty!"
  exit 1
fi

. "$(dirname "$0")/../config.conf"
LOG_FILE="$(dirname "$0")/../fb/log.txt"

if [[ -z "${reshare_page_id}" ]]; then
  echo "INFO: reshare_page_id is blank in config.conf. Skipping random reshare."
  exit 0
fi

# Check if log file exists and has content
if [[ ! -f "$LOG_FILE" ]]; then
  echo "ERROR: Log file not found: $LOG_FILE"
  exit 1
fi

if [[ ! -s "$LOG_FILE" ]]; then
  echo "ERROR: Log file is empty: $LOG_FILE"
  exit 1
fi

# Get episodes
episodes=$(awk '{for(i=1;i<=NF;i++) if ($i=="Episode") print $(i+1)}' "$LOG_FILE" | sort -u)

if [[ -z "$episodes" ]]; then
  echo "ERROR: No episodes found in log file"
  exit 1
fi

echo "Available episodes: $episodes"

# Pick random episode and frame
random_episode=$(echo "$episodes" | shuf -n 1)
random_line=$(grep "Episode ${random_episode}" "$LOG_FILE" | shuf -n 1)

if [[ -z "$random_line" ]]; then
  echo "ERROR: No frames found for episode $random_episode"
  exit 1
fi

frame_info=$(echo "$random_line" | awk -F 'https' '{print $1}' | sed 's/\[√\] *//')
frame_url=$(echo "$random_line" | awk '{print $NF}')
message="Random frame. ${frame_info}"

echo "DEBUG: Selected episode: ${random_episode}"
echo "DEBUG: Frame info: ${frame_info}"
echo "DEBUG: Frame URL: ${frame_url}"
echo "DEBUG: Message: ${message}"
echo ""

# First, verify token has access to the page
page_id="${reshare_page_id}"
echo "Verifying page access..."
verify_response=$(curl -s "${FRMENV_API_ORIGIN}/${FRMENV_FBAPI_VER}/me/accounts?access_token=${FRMENV_FBTOKEN}")

# Check if we can see the page
has_page=$(echo "$verify_response" | jq -r ".data[]? | select(.id==\"${page_id}\") | .id" 2>/dev/null)

if [[ -z "$has_page" ]]; then
  echo "WARNING: Page ${page_id} not found in token's accessible pages"
  echo "Available pages:"
  echo "$verify_response" | jq -r '.data[]? | "  - \(.id): \(.name)"' 2>/dev/null
  echo ""
  echo "You may need to:"
  echo "1. Regenerate token with 'pages_manage_posts' permission"
  echo "2. Make sure you selected the correct page when generating the token"
  echo ""
fi

# Try posting
echo "Attempting to post..."
response=$(
  curl -s -w "\n%{http_code}" -X POST \
    -F "message=${message}" \
    -F "link=${frame_url}" \
    "${FRMENV_API_ORIGIN}/${FRMENV_FBAPI_VER}/${page_id}/feed?access_token=${FRMENV_FBTOKEN}"
)

body=$(echo "$response" | head -n -1)
status=$(echo "$response" | tail -n 1)

echo "Response status: $status"

if [[ "$status" != "200" ]]; then
  echo ""
  echo "ERROR: Failed to share $frame_url"
  echo "Facebook response: $body"
  echo ""
  
  # Parse error details
  error_code=$(echo "$body" | jq -r '.error.code // empty' 2>/dev/null)
  error_msg=$(echo "$body" | jq -r '.error.message // empty' 2>/dev/null)
  error_type=$(echo "$body" | jq -r '.error.type // empty' 2>/dev/null)
  
  echo "Error details:"
  echo "  Type: $error_type"
  echo "  Code: $error_code"
  echo "  Message: $error_msg"
  echo ""
  
  if [[ "$error_code" == "200" ]]; then
    echo "SOLUTION: Permissions error (#200) means your token is missing posting permissions."
    echo ""
    echo "To fix this:"
    echo "1. Go to: https://developers.facebook.com/tools/explorer/"
    echo "2. Select your app"
    echo "3. Click 'Get Token' → 'Get Page Access Token'"
    echo "4. Select the page: ${page_id}"
    echo "5. Make sure these permissions are CHECKED:"
    echo "   - pages_manage_posts"
    echo "   - pages_read_engagement"
    echo "   - pages_show_list"
    echo "6. Generate the token and update your TOK_FB secret"
    echo ""
  elif [[ "$error_code" == "190" ]]; then
    echo "SOLUTION: Token is invalid or expired (#190)."
    echo "You need to generate a new Page Access Token."
    echo ""
  fi
  
  exit 1
fi

post_id=$(echo "$body" | jq -r '.id // empty' 2>/dev/null)
echo ""
echo "SUCCESS! Shared: $frame_info"
echo "Post URL: https://facebook.com/${post_id}"
echo "Frame URL: $frame_url"
