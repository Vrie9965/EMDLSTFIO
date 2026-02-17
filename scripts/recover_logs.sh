#!/bin/bash
# File: EOFIO12/scripts/recover_logs.sh
# Recovers missing episode logs from Facebook page posts

: "${FRMENV_FBTOKEN:=${TOK_FB:-}}"
if [[ -z "$FRMENV_FBTOKEN" ]]; then
  echo "ERROR: FRMENV_FBTOKEN is empty!"
  exit 1
fi

. "$(dirname "$0")/../config.conf"
LOG_FILE="$(dirname "$0")/../fb/log.txt"
RECOVERED_FILE="$(dirname "$0")/../fb/recovered_log.txt"

# Episodes to recover with their album IDs
declare -A episode_albums
episode_albums["01"]="122102865896200694"
episode_albums["02"]="122119297598200694"

# Album for frames 1-100 of Episode 01
first_frames_album="122102861978200694"

# Always create recovered file and write header
cat > "$RECOVERED_FILE" << EOF
# Recovery Log - $(date)
# Attempting to recover Episode 01 and 02

EOF

echo "Starting recovery process..."
echo "Configuration check:"
echo "  API Origin: ${FRMENV_API_ORIGIN}"
echo "  API Version: ${FRMENV_FBAPI_VER}"
echo "  Token present: $([ -n "$FRMENV_FBTOKEN" ] && echo 'YES' || echo 'NO')"
echo ""

total_recovered=0
recovered_frames=()

# METHOD 0: Try to find frames 1-100 FIRST (before rate limits hit)
echo "=========================================="
echo "METHOD 0: Searching for frames 1-100"
echo "Album: $first_frames_album"
echo "=========================================="
echo ""

echo "# Episode 01 Frames 1-100 - Album: $first_frames_album" >> "$RECOVERED_FILE"

url="${FRMENV_API_ORIGIN}/${FRMENV_FBAPI_VER}/${first_frames_album}/photos?fields=id,name,created_time&limit=100&access_token=${FRMENV_FBTOKEN}"

page_count=0
found_early=0

while [[ -n "$url" ]] && [[ $page_count -lt 2 ]]; do
  page_count=$((page_count + 1))
  echo "Fetching page $page_count for early frames..."
  
  response=$(curl -s "$url")
  
  error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
  if [[ -n "$error_msg" ]]; then
    echo "Early frames search failed: $error_msg"
    echo "# Early frames album error: $error_msg" >> "$RECOVERED_FILE"
    break
  fi
  
  photos=$(echo "$response" | jq -r '.data[]? | @json' 2>/dev/null)
  if [[ -z "$photos" ]]; then
    echo "No photos found in early frames album"
    break
  fi
  
  # Show sample
  if [[ $page_count -eq 1 ]]; then
    echo "Sample photo names:"
    echo "$photos" | head -3 | while IFS= read -r photo; do
      name=$(echo "$photo" | jq -r '.name // "NO NAME"' 2>/dev/null)
      id=$(echo "$photo" | jq -r '.id // "NO ID"' 2>/dev/null)
      echo "  - ID: $id, Name: $name"
    done
    echo ""
  fi
  
  # Process photos
  while IFS= read -r photo; do
    if [[ -n "$photo" ]]; then
      post_id=$(echo "$photo" | jq -r '.id // empty' 2>/dev/null)
      name=$(echo "$photo" | jq -r '.name // empty' 2>/dev/null)
      
      if [[ -n "$post_id" ]]; then
        # Try to extract frame number
        frame_num=""
        if [[ -n "$name" ]] && echo "$name" | grep -qiE "Frame[[:space:]]*[0-9]+"; then
          frame_num=$(echo "$name" | grep -oiE "Frame[[:space:]]*[0-9]+" | grep -oE "[0-9]+" | head -1)
        fi
        
        # Only process if frame <= 100 or no frame found (assume sequential)
        if [[ -z "$frame_num" ]] || [[ $frame_num -le 100 ]]; then
          # Use extracted frame or increment
          if [[ -z "$frame_num" ]]; then
            frame_num=$((found_early + 1))
          fi
          
          # Check for duplicate
          frame_key="01-${frame_num}"
          if [[ ! " ${recovered_frames[@]} " =~ " ${frame_key} " ]]; then
            fb_url="https://facebook.com/${post_id}"
            log_entry="[√] Frame: ${frame_num}, Episode 01 ${fb_url}"
            echo "$log_entry" >> "$RECOVERED_FILE"
            
            recovered_frames+=("$frame_key")
            found_early=$((found_early + 1))
            total_recovered=$((total_recovered + 1))
            
            if (( found_early % 25 == 0 )); then
              echo "  Processed $found_early early frames..."
            fi
          fi
        fi
      fi
    fi
  done <<< "$photos"
  
  url=$(echo "$response" | jq -r '.paging.next // empty' 2>/dev/null)
  sleep 1
done

echo "Found $found_early frames (1-100 range)"
echo "" >> "$RECOVERED_FILE"
echo ""

# Longer delay before next batch to avoid rate limits
sleep 2

# Process each episode
for episode in "01" "02"; do
  album_id="${episode_albums[$episode]}"
  
  echo "=========================================="
  echo "RECOVERING EPISODE $episode"
  echo "Album ID: $album_id"
  echo "=========================================="
  echo ""
  
  echo "# Episode $episode - Album: $album_id" >> "$RECOVERED_FILE"
  
  # Fetch photos from this specific album
  url="${FRMENV_API_ORIGIN}/${FRMENV_FBAPI_VER}/${album_id}/photos?fields=id,name,created_time&limit=100&access_token=${FRMENV_FBTOKEN}"
  
  page_count=0
  episode_count=0
  
  # Array to store all photos for this episode
  declare -a photo_data
  
  while [[ -n "$url" ]]; do
    page_count=$((page_count + 1))
    echo "Fetching page $page_count..."
    
    response=$(curl -s "$url")
    
    # Check for errors
    error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
    if [[ -n "$error_msg" ]]; then
      echo "ERROR: $error_msg"
      echo "# ERROR on Episode $episode: $error_msg" >> "$RECOVERED_FILE"
      break
    fi
    
    # Get photos from this page
    photos=$(echo "$response" | jq -r '.data[]? | @json' 2>/dev/null)
    if [[ -z "$photos" ]]; then
      echo "No more photos found."
      break
    fi
    
    # Store photos
    while IFS= read -r photo; do
      if [[ -n "$photo" ]]; then
        photo_data+=("$photo")
      fi
    done <<< "$photos"
    
    photos_count=$(echo "$photos" | wc -l)
    episode_count=$((episode_count + photos_count))
    echo "  Found $photos_count photos (total for episode: $episode_count)"
    
    # Show sample of first 3 photo names to debug
    if [[ $page_count -eq 1 ]]; then
      echo ""
      echo "Sample photo names from this album:"
      echo "$photos" | head -3 | while IFS= read -r photo; do
        name=$(echo "$photo" | jq -r '.name // "NO NAME"' 2>/dev/null)
        id=$(echo "$photo" | jq -r '.id // "NO ID"' 2>/dev/null)
        echo "  - ID: $id"
        echo "    Name: $name"
      done
      echo ""
    fi
    
    # Get next page
    url=$(echo "$response" | jq -r '.paging.next // empty' 2>/dev/null)
    sleep 0.5
  done
  
  echo ""
  echo "Total photos found for Episode $episode: $episode_count"
  echo ""
  
  # Now process all photos for this episode
  if [[ ${#photo_data[@]} -gt 0 ]]; then
    echo "Processing ${#photo_data[@]} photos..."
    
    frame_num=1
    for photo in "${photo_data[@]}"; do
      post_id=$(echo "$photo" | jq -r '.id // empty' 2>/dev/null)
      name=$(echo "$photo" | jq -r '.name // empty' 2>/dev/null)
      
      if [[ -n "$post_id" ]]; then
        # Try to extract frame number from name if it exists
        if [[ -n "$name" ]] && echo "$name" | grep -qiE "Frame[[:space:]]*[0-9]+"; then
          extracted_frame=$(echo "$name" | grep -oiE "Frame[[:space:]]*[0-9]+" | grep -oE "[0-9]+" | head -1)
          if [[ -n "$extracted_frame" ]]; then
            frame_num=$extracted_frame
          fi
        fi
        
        # Construct Facebook URL
        fb_url="https://facebook.com/${post_id}"
        
        # Write in same format as original log
        log_entry="[√] Frame: ${frame_num}, Episode ${episode} ${fb_url}"
        echo "$log_entry" >> "$RECOVERED_FILE"
        
        total_recovered=$((total_recovered + 1))
        
        # Only show progress every 100 frames
        if (( frame_num % 100 == 0 )); then
          echo "  Processed frame $frame_num..."
        fi
        
        frame_num=$((frame_num + 1))
      fi
    done
    
    echo "Wrote $episode_count frames for Episode $episode"
  else
    echo "# No photos found for Episode $episode" >> "$RECOVERED_FILE"
    echo "No photos found for Episode $episode"
  fi
  
  echo "" >> "$RECOVERED_FILE"
  echo ""
  
  # Clear array for next episode
  unset photo_data
  declare -a photo_data
done

# METHOD 6: Try to find missing frames 1-100 for Episode 01
echo "=========================================="
echo "METHOD 6: Searching for missing frames 1-100"
echo "=========================================="
echo ""

# Try the original album set ID that was in the first example URLs
fallback_album="122102861978200694"
echo "Trying fallback album: $fallback_album"
echo "# Attempting to find missing frames 1-100 from fallback album" >> "$RECOVERED_FILE"

url="${FRMENV_API_ORIGIN}/${FRMENV_FBAPI_VER}/${fallback_album}/photos?fields=id,name,created_time&limit=100&access_token=${FRMENV_FBTOKEN}"

page_count=0
found_missing=0

while [[ -n "$url" ]] && [[ $page_count -lt 2 ]]; do
  page_count=$((page_count + 1))
  echo "Fetching page $page_count from fallback album..."
  
  response=$(curl -s "$url")
  
  error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
  if [[ -n "$error_msg" ]]; then
    echo "Fallback method failed: $error_msg"
    echo "# Fallback album failed: $error_msg" >> "$RECOVERED_FILE"
    break
  fi
  
  photos=$(echo "$response" | jq -r '.data[]? | @json' 2>/dev/null)
  if [[ -z "$photos" ]]; then
    break
  fi
  
  # Process photos looking for Episode 01 frames 1-100
  while IFS= read -r photo; do
    if [[ -n "$photo" ]]; then
      post_id=$(echo "$photo" | jq -r '.id // empty' 2>/dev/null)
      name=$(echo "$photo" | jq -r '.name // empty' 2>/dev/null)
      
      # Check if this is Episode 01 and extract frame number
      if [[ -n "$name" ]] && echo "$name" | grep -qiE "(Episode[[:space:]]*01|Season[[:space:]]*1.*Episode[[:space:]]*01)"; then
        frame_num=$(echo "$name" | grep -oiE "Frame[[:space:]]*[0-9]+" | grep -oE "[0-9]+" | head -1)
        
        if [[ -n "$frame_num" ]] && [[ $frame_num -le 100 ]]; then
          fb_url="https://facebook.com/${post_id}"
          log_entry="[√] Frame: ${frame_num}, Episode 01 ${fb_url}"
          echo "$log_entry" >> "$RECOVERED_FILE"
          echo "  Found missing frame: $frame_num"
          found_missing=$((found_missing + 1))
          total_recovered=$((total_recovered + 1))
        fi
      fi
    fi
  done <<< "$photos"
  
  url=$(echo "$response" | jq -r '.paging.next // empty' 2>/dev/null)
  sleep 0.5
done

if [[ $found_missing -gt 0 ]]; then
  echo "Found $found_missing missing frames!"
else
  echo "No missing frames found in fallback album"
  echo "# No missing frames 1-100 found" >> "$RECOVERED_FILE"
fi

echo ""
echo "" >> "$RECOVERED_FILE"

echo "=========================================="
echo "RECOVERY COMPLETE!"
echo "=========================================="
echo "Total frames recovered: $total_recovered"
echo "Recovered log saved to: $RECOVERED_FILE"
echo ""

if [[ $total_recovered -gt 0 ]]; then
  echo "SUCCESS! Found $total_recovered frames across Episode 01 and 02"
  echo "Note: If frames 1-100 are still missing, they may be in a different"
  echo "album or posted separately. You can manually add them if found."
  echo ""
  echo "You can now merge recovered_log.txt with log.txt"
else
  echo "WARNING: No frames were recovered."
  echo "Check the recovered_log.txt file for error messages."
fi

# Always show file size
if [[ -f "$RECOVERED_FILE" ]]; then
  file_size=$(wc -c < "$RECOVERED_FILE")
  echo "Recovered log file size: $file_size bytes"
fi
