#!/bin/sh
set -eu

if [ "${radarr_eventtype:-}" = "Test" ]; then
  printf '%s\n' "swiftTorrent Radarr custom script is installed; On Grab will send the torrent hash and movie IDs."
  exit 0
fi

: "${radarr_download_id:?radarr_download_id is required}"
: "${radarr_movie_title:?radarr_movie_title is required}"

post_grab() {
  base_url="${1%/}"
  printf '%s\n' "swiftTorrent Radarr grab callback: event=${radarr_eventtype:-unknown} title=${radarr_movie_title} imdb=${radarr_movie_imdbid:-missing} tmdb=${radarr_movie_tmdbid:-missing} downloadId=${radarr_download_id} endpoint=${base_url}/api/arr/grab" >&2
  curl --fail --silent --show-error --connect-timeout 3 --max-time 12 \
    --request POST \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "source=radarr" \
    --data-urlencode "eventType=${radarr_eventtype:-Grab}" \
    --data-urlencode "downloadId=${radarr_download_id}" \
    --data-urlencode "type=movie" \
    --data-urlencode "title=${radarr_movie_title}" \
    --data-urlencode "year=${radarr_movie_year:-}" \
    --data-urlencode "imdbId=${radarr_movie_imdbid:-}" \
    --data-urlencode "tmdbId=${radarr_movie_tmdbid:-}" \
    --data-urlencode "releaseTitle=${radarr_release_title:-}" \
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
