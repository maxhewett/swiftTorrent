#!/bin/zsh
set -eu

: "${radarr_download_id:?radarr_download_id is required}"
: "${radarr_movie_title:?radarr_movie_title is required}"

WEBUI_BASE_URL="${SWIFTTORRENT_WEBUI_BASE_URL:-http://127.0.0.1:8080}"

curl --fail --silent --show-error \
  --request POST \
  --header "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "source=radarr" \
  --data-urlencode "downloadId=${radarr_download_id}" \
  --data-urlencode "type=movie" \
  --data-urlencode "title=${radarr_movie_title}" \
  --data-urlencode "year=${radarr_movie_year:-}" \
  --data-urlencode "imdbId=${radarr_movie_imdbid:-}" \
  --data-urlencode "tmdbId=${radarr_movie_tmdbid:-}" \
  "${WEBUI_BASE_URL}/api/arr/grab"
