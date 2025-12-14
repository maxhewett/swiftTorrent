//
//  TorrentCore.mm
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

// TorrentCore.mm
#import "TorrentCore.h"

#include <cstdio>
#include <string>
#include <vector>

#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/torrent_flags.hpp>
#include <libtorrent/hex.hpp>          // lt::aux::to_hex
#include <libtorrent/sha1_hash.hpp>    // info_hash_t

namespace lt = libtorrent;

struct STSession {
    lt::session ses;
    explicit STSession(lt::settings_pack pack) : ses(std::move(pack)) {}
};

// Cache values for the latest st_get_torrents() snapshot.
// Valid until next st_get_torrents() call.
static std::vector<std::string> g_name_cache;
static std::vector<std::string> g_id_cache;

static void write_err(char* buf, int32_t len, const char* msg) {
    if (!buf || len <= 0) return;
    std::snprintf(buf, (size_t)len, "%s", msg ? msg : "");
}

STSessionRef st_session_create(uint16_t listen_port_start, uint16_t /*listen_port_end*/) {
    lt::settings_pack pack;

    pack.set_int(lt::settings_pack::alert_mask,
                 lt::alert_category::error | lt::alert_category::status);

    // Explicit listen interfaces (libtorrent 2.0 style)
    {
        char buf[128];
        std::snprintf(buf, sizeof(buf), "0.0.0.0:%u,[::]:%u", listen_port_start, listen_port_start);
        pack.set_str(lt::settings_pack::listen_interfaces, buf);
    }

    // Enable discovery
    pack.set_bool(lt::settings_pack::enable_dht, true);
    pack.set_bool(lt::settings_pack::enable_lsd, true);
    pack.set_bool(lt::settings_pack::enable_upnp, true);
    pack.set_bool(lt::settings_pack::enable_natpmp, true);

    // Help DHT bootstrap quickly
    pack.set_str(
        lt::settings_pack::dht_bootstrap_nodes,
        "router.bittorrent.com:6881,"
        "dht.transmissionbt.com:6881,"
        "router.utorrent.com:6881"
    );

    auto* s = new STSession(std::move(pack));
    return (STSessionRef)s;
}

void st_session_destroy(STSessionRef session) {
    if (!session) return;
    delete (STSession*)session;
}

bool st_add_magnet(STSessionRef session,
                   const char* magnet_uri,
                   const char* save_path,
                   char* err_buf,
                   int32_t err_buf_len) {
    if (!session || !magnet_uri || !save_path) {
        write_err(err_buf, err_buf_len, "Invalid arguments");
        return false;
    }

    auto* s = (STSession*)session;

    lt::error_code ec;
    lt::add_torrent_params p = lt::parse_magnet_uri(std::string(magnet_uri), ec);
    if (ec) {
        write_err(err_buf, err_buf_len, ec.message().c_str());
        return false;
    }

    // Dev assist: if magnet has no trackers, add a couple public ones
    if (p.trackers.empty()) {
        p.trackers.push_back("udp://tracker.opentrackr.org:1337/announce");
        p.trackers.push_back("udp://open.stealth.si:80/announce");
    }

    p.save_path = std::string(save_path);

    s->ses.add_torrent(std::move(p), ec);
    if (ec) {
        write_err(err_buf, err_buf_len, ec.message().c_str());
        return false;
    }

    write_err(err_buf, err_buf_len, "");
    return true;
}

int32_t st_get_torrents(STSessionRef session, STTorrentStatus* out_items, int32_t max_items) {
    if (!session || !out_items || max_items <= 0) return 0;

    auto* s = (STSession*)session;

    std::vector<lt::torrent_handle> handles = s->ses.get_torrents();

    g_name_cache.clear();
    g_id_cache.clear();
    g_name_cache.reserve(handles.size());
    g_id_cache.reserve(handles.size());

    int32_t count = 0;

    for (auto& h : handles) {
        if (count >= max_items) break;

        lt::torrent_status st = h.status();

        // Cache name
        g_name_cache.push_back(st.name);

        // Cache stable id (best info-hash; hex)
        {
            auto ih = st.info_hashes.get_best();
            g_id_cache.push_back(lt::aux::to_hex(ih));
        }

        STTorrentStatus out{};
        out.progress = st.progress;

        out.total_wanted = (int64_t)st.total_wanted;
        out.total_wanted_done = (int64_t)st.total_wanted_done;

        out.download_rate = (int32_t)st.download_rate;
        out.upload_rate = (int32_t)st.upload_rate;

        out.num_peers = (int32_t)st.num_peers;
        out.num_seeds = (int32_t)st.num_seeds;

        out.state = (int32_t)st.state;

        out.is_seeding = (st.state == lt::torrent_status::seeding);
        out.is_paused  = (st.flags & lt::torrent_flags::paused) != 0;
        out.has_error  = (bool)st.errc;

        out_items[count++] = out;
    }

    return count;
}

const char* st_get_torrent_name(STSessionRef /*session*/, int32_t index) {
    if (index < 0) return "";
    if ((size_t)index >= g_name_cache.size()) return "";
    return g_name_cache[(size_t)index].c_str();
}

const char* st_get_torrent_id(STSessionRef /*session*/, int32_t index) {
    if (index < 0) return "";
    if ((size_t)index >= g_id_cache.size()) return "";
    return g_id_cache[(size_t)index].c_str();
}
