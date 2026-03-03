#!/bin/zsh
set -eu

: "${sonarr_download_id:?sonarr_download_id is required}"
: "${sonarr_series_title:?sonarr_series_title is required}"

WEBUI_BASE_URL="${SWIFTTORRENT_WEBUI_BASE_URL:-http://127.0.0.1:8080}"

curl --fail --silent --show-error \
  --request POST \
  --header "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "source=sonarr" \
  --data-urlencode "downloadId=${sonarr_download_id}" \
  --data-urlencode "type=show" \
  --data-urlencode "title=${sonarr_series_title}" \
  --data-urlencode "year=${sonarr_series_year:-}" \
  --data-urlencode "imdbId=${sonarr_series_imdbid:-}" \
  --data-urlencode "tvdbId=${sonarr_series_tvdbid:-}" \
  "${WEBUI_BASE_URL}/api/arr/grab"
