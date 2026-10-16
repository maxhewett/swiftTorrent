#!/bin/sh
set -eu

: "${sonarr_download_id:?sonarr_download_id is required}"
: "${sonarr_series_title:?sonarr_series_title is required}"

post_grab() {
  base_url="${1%/}"
  printf '%s\n' "swiftTorrent Sonarr grab callback: event=${sonarr_eventtype:-unknown} title=${sonarr_series_title} tvdb=${sonarr_series_tvdbid:-missing} downloadId=${sonarr_download_id} endpoint=${base_url}/api/arr/grab" >&2
  curl --fail --silent --show-error --connect-timeout 3 --max-time 12 \
    --request POST \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "source=sonarr" \
    --data-urlencode "eventType=${sonarr_eventtype:-Grab}" \
    --data-urlencode "downloadId=${sonarr_download_id}" \
    --data-urlencode "type=show" \
    --data-urlencode "title=${sonarr_series_title}" \
    --data-urlencode "year=${sonarr_series_year:-}" \
    --data-urlencode "imdbId=${sonarr_series_imdbid:-}" \
    --data-urlencode "tvdbId=${sonarr_series_tvdbid:-}" \
    --data-urlencode "seasonNumber=${sonarr_release_seasonnumber:-}" \
    --data-urlencode "episodeNumbers=${sonarr_release_episodenumbers:-}" \
    --data-urlencode "releaseTitle=${sonarr_release_title:-}" \
    "${base_url}/api/arr/grab"
}

if [ -n "${SWIFTTORRENT_WEBUI_BASE_URL:-}" ]; then
  post_grab "$SWIFTTORRENT_WEBUI_BASE_URL"
  exit $?
fi

# swiftTorrent's WebUI port is configurable. Try its default and the 8180 port
# commonly used by Transmission-compatible download clients.
for port in 8080 8180; do
  if post_grab "http://127.0.0.1:${port}"; then exit 0; fi
done
exit 1
