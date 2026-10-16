# Radarr and Sonarr integration

swiftTorrent's Transmission-compatible download client connection receives torrent details, but not the media IDs Radarr and Sonarr know. The included custom scripts send those IDs to swiftTorrent when a release is grabbed. This is what allows swiftTorrent to match a torrent to the intended movie, series, season, and episodes reliably.

## Install the custom scripts

1. Locate `radarr_swifttorrent_grab.sh` and `sonarr_swifttorrent_grab.sh` from the swiftTorrent distribution. In a source checkout they are in `scripts/`; packaged builds include them in the app's `Contents/Resources/ArrScripts/` folder.
2. Copy the relevant script to a location executable by the Radarr or Sonarr service account. If those services run in Docker or on another machine, copy the script into the container/host and make sure its path is visible there. The script must be executable (`chmod +x <script-path>`).
3. In Radarr, open **Settings → Connect → + → Custom Script**. Set the script path and enable **On Grab**. Repeat in Sonarr with its corresponding script.
4. Use **Test** in the custom script settings. The test event does not include a torrent hash or media IDs; the included scripts recognize it and report that they are installed.

The scripts try `http://127.0.0.1:8080` and `http://127.0.0.1:8180` by default. If swiftTorrent uses another Web UI port, or Arr runs in a container/on another machine, set `SWIFTTORRENT_WEBUI_BASE_URL` in that custom script's environment to a URL Arr can reach, for example `http://host.docker.internal:8180` for Docker Desktop or `http://<swiftTorrent-host>:<web-ui-port>` for a remote host.

If the Radarr/Sonarr instance can reach swiftTorrent directly but cannot execute a local script, configure a **Webhook** connection with the **On Grab** event and URL `http://<swiftTorrent-host>:<web-ui-port>/api/arr/grab`. The callback accepts the webhook's nested movie or series data.

## Confirm callbacks

After the next grab, swiftTorrent should log an `[ARR] Grab hint received` entry followed by the torrent hash match and metadata selection. If there is no callback, inspect the custom script's event log in Arr and confirm the script path, execution permission, and Web UI URL. If the callback arrives but cannot associate the torrent, compare the supplied download ID with the torrent hash shown in swiftTorrent's `/api/arr/diagnostics` endpoint. Lookup and matching errors are also recorded in swiftTorrent's runtime log.

The script's stderr output includes the callback URL and supplied IDs to help diagnose a failed request. Do not expose the Arr API key here: the callback scripts do not need it because the endpoint is local to swiftTorrent.

The bundled Radarr and Sonarr marks in the queue are the respective projects' logos and are used only to indicate the source of a transfer.
