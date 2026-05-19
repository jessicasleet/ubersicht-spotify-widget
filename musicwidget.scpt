-- musicwidget.scpt
-- simple spotify status + metadata + album art fetcher for ubersicht widget
-- uses apple script bridge to spotify app (no web api, no auth, no premium required)

if application "Spotify" is not running then
	-- if spotify not open at all, return safe default json object (stops crashing when closed)
	return "{\"app\":\"Spotify\",\"state\":\"closed\",\"track\":\"no music playing ✰˚.⋆\",\"artist\":\"\",\"duration\":0,\"position\":0,\"image\":\"\"}"
end if

tell application "Spotify"
	try
		-- get current playback state
		set currentState to player state
		
		-- convert applescript enum into plain string for frontend use
		if currentState is playing then
			set stateText to "playing"
		else if currentState is paused then
			set stateText to "paused"
		else
			set stateText to "stopped"
		end if
		
		-- pull core track metadata from current track object
		set trackname to name of current track
		set artistname to artist of current track
		set albumname to album of current track
		set trackduration to (duration of current track) / 1000
		set playerposition to player position
		set artURL to artwork url of current track
		
	on error
		-- fallback if spotify api call fails (no track, no permission, etc)
		return "{\"app\":\"Spotify\",\"state\":\"stopped\",\"track\":\"no music playing ✰˚.⋆\",\"artist\":\"\",\"duration\":0,\"position\":0,\"image\":\"\"}"
	end try
end tell


-- download art from spotify CDN & convert to base-64; cache to avoid refresh
set CACHE_DIR to (POSIX path of (path to home folder)) & ".spotify_art_cache"
set CURRENT_TRACK_FILE to CACHE_DIR & "/current_track_id.txt"
set CACHED_ART_FILE to CACHE_DIR & "/current_art.b64"

-- shell script to do:
-- 1. cache directory creation
-- 2. track identity hashing (via art url)
-- 3. conditional download
-- 4. base64 encoding for embedding in json
set base64Art to do shell script "
mkdir -p " & quoted form of CACHE_DIR & "

ART_URL=" & quoted form of artURL & "

-- generate simple track key based on artwork url
-- used to detect when track changes
TRACK_KEY=$(echo \"$ART_URL\" | md5)
CACHED_KEY=\"\"

-- read last stored track key if it exists
if [ -f " & quoted form of CURRENT_TRACK_FILE & " ]; then
    CACHED_KEY=$(cat " & quoted form of CURRENT_TRACK_FILE & ")
fi

-- if same track, reuse cached image instead of re-downloading
if [ \"$TRACK_KEY\" = \"$CACHED_KEY\" ] && [ -f " & quoted form of CACHED_ART_FILE & " ]; then
    cat " & quoted form of CACHED_ART_FILE & "
else
    -- otherwise fetch fresh artwork
    TMP_IMG=" & quoted form of CACHE_DIR & "/tmp_art.jpg
    
    -- silent download from spotify cdn
    curl -s -o \"$TMP_IMG\" \"$ART_URL\"
    
    -- only proceed if image actually downloaded correctly
    if [ -s \"$TMP_IMG\" ]; then
        -- convert image to base64 for embedding in json payload
        base64 -i \"$TMP_IMG\" -o " & quoted form of CACHED_ART_FILE & "
        
        -- store current track key for future cache validation
        echo \"$TRACK_KEY\" > " & quoted form of CURRENT_TRACK_FILE & "
        
        -- output encoded image
        cat " & quoted form of CACHED_ART_FILE & "
    fi
fi
"

-- remove newline characters from base-64 output (makes sure json string is valid)
set base64Art to do shell script "echo " & quoted form of base64Art & " | tr -d '\\n'"

-- return playback state, metadata, timing & art
return "{\"app\":\"Spotify\",\"state\":\"" & stateText & "\",\"track\":\"" & trackname & "\",\"artist\":\"" & artistname & "\",\"album\":\"" & albumname & "\",\"duration\":" & trackduration & ",\"position\":" & playerposition & ",\"image\":\"" & base64Art & "\"}"
