# Radarr and Sonarr metadata matching

swiftTorrent receives authoritative media IDs from Radarr and Sonarr through an **On Grab** callback. The Transmission RPC `torrent-add` request contains the magnet and save path, but does not include the Radarr movie or Sonarr series IDs. Without the grab callback, swiftTorrent can only infer a match from the release name. The callback endpoint accepts both the included scripts' form fields and nested Radarr/Sonarr webhook JSON.

## Configure the grab callback

1. Make the matching script available on the machine running Radarr or Sonarr. The scripts are `scripts/radarr_swifttorrent_grab.sh` and `scripts/sonarr_swifttorrent_grab.sh` in this repository. They are executable and use `/bin/sh` for portability.
2. For local installs, the scripts try both `http://127.0.0.1:8080` and `http://127.0.0.1:8180`, since swiftTorrent's WebUI port is configurable and 8180 is also a common Transmission-compatible client port. If Radarr/Sonarr runs in Docker or on another machine, set `SWIFTTORRENT_WEBUI_BASE_URL` to an address reachable from the container/machine, such as `http://host.docker.internal:8180` for Docker Desktop or `http://<swiftTorrent-host>:<web-ui-port>` for a remote host. The script prints each callback URL and supplied IDs; curl errors are returned to the Arr custom-script log.
3. In Radarr or Sonarr, add a **Custom Script** connection with the **On Grab** trigger and select the corresponding script. Keep the script’s environment variables enabled; it submits the service’s download ID, title, year, and IMDb/TMDb/TVDB IDs to `/api/arr/grab`.
4. Grab a test item and inspect swiftTorrent’s Diagnostics logs. A successful callback logs `[ARR] Grab hint received` followed by whether its download hash matched a current torrent. If the hint was received before the torrent was added, it remains stored and will be used when that hash appears. If there is no `[ARR]` log at all, the custom script did not reach swiftTorrent; check its output in the Arr logs for the endpoint and HTTP/network error.

Alternatively, configure a Radarr or Sonarr Webhook connection with the **On Grab** event and URL `http://<swiftTorrent-host>:<web-ui-port>/api/arr/grab`. The callback accepts the webhook's nested `movie` or `series` object and extracts its title and metadata IDs.

The callback also works when it arrives after the torrent has been added: swiftTorrent links the hint using the normalized torrent info hash and refreshes metadata as soon as it finds that torrent.
