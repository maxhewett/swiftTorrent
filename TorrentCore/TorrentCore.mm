//
//  TorrentCore.mm
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

#import "TorrentCore.h"

#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/torrent_status.hpp>

#include <vector>
#include <string>
#include <cstring>
#include <mutex>

namespace lt = libtorrent;

struct SessionWrap {
    lt::session sess;
    std::mutex  mtx;

    // Snapshot of handles for index-based getters
    std::vector<lt::torrent_handle> handles;

    // Snapshot strings (stable pointers until next refresh)
    std::vector<std::string> names;
    std::vector<std::string> ids;
};

static std::string to_hex_id(const lt::torrent_handle& h) {
    // For v1 torrents: info-hash v1 is sha1 (20 bytes) => 40 hex
    // For v2: may have v2 hash; we’ll prefer v1 when available.
    lt::info_hash_t ih = h.info_hashes();
    lt::sha1_hash v1 = ih.v1;
    auto const* b = v1.data();

    static const char* hex = "0123456789abcdef";
    std::string out;
    out.resize(40);

    for (int i = 0; i < 20; ++i) {
        unsigned char c = static_cast<unsigned char>(b[i]);
        out[i*2]     = hex[(c >> 4) & 0xF];
        out[i*2 + 1] = hex[c & 0xF];
    }
    return out;
}

static lt::torrent_handle find_handle_by_id(SessionWrap* w, const char* torrent_id_hex) {
    if (!torrent_id_hex) return lt::torrent_handle();

    std::string target(torrent_id_hex);
    for (auto const& h : w->handles) {
        if (!h.is_valid()) continue;
        if (to_hex_id(h) == target) return h;
    }
    return lt::torrent_handle();
}

extern "C" {

STSessionRef st_session_create(uint16_t listen_port_start, uint16_t listen_port_end) {
    auto* w = new SessionWrap();

    lt::settings_pack p;
    p.set_bool(lt::settings_pack::enable_dht, true);
    p.set_bool(lt::settings_pack::enable_lsd, true);
    p.set_bool(lt::settings_pack::enable_upnp, true);
    p.set_bool(lt::settings_pack::enable_natpmp, true);

    // Libtorrent 2.x uses listen_interfaces
    // Example: "0.0.0.0:6881,[::]:6881"
    std::string iface = "0.0.0.0:" + std::to_string(listen_port_start) + ",[::]:" + std::to_string(listen_port_start);
    p.set_str(lt::settings_pack::listen_interfaces, iface);

    w->sess.apply_settings(p);
    return (STSessionRef)w;
}

void st_session_destroy(STSessionRef session) {
    if (!session) return;
    auto* w = (SessionWrap*)session;
    delete w;
}

bool st_add_magnet(
    STSessionRef session,
    const char* magnet_uri,
    const char* save_path,
    char* err_buf,
    int32_t err_buf_len
) {
    if (!session || !magnet_uri || !save_path) return false;

    auto* w = (SessionWrap*)session;

    try {
        lt::add_torrent_params atp = lt::parse_magnet_uri(magnet_uri);
        atp.save_path = save_path;

        // Don't let session auto-management override pause/resume decisions
        atp.flags &= ~lt::torrent_flags::auto_managed;

        // Ensure it isn't created paused
        atp.flags &= ~lt::torrent_flags::paused;

        std::lock_guard<std::mutex> lock(w->mtx);

        // ✅ Synchronous add, returns a valid handle immediately
        lt::torrent_handle h = w->sess.add_torrent(std::move(atp));

        if (h.is_valid()) {
            h.unset_flags(lt::torrent_flags::auto_managed);
            h.resume(); // ✅ starts now
        }

        return true;
    } catch (std::exception const& e) {
        if (err_buf && err_buf_len > 0) {
            std::snprintf(err_buf, (size_t)err_buf_len, "%s", e.what());
        }
        return false;
    }
}

int32_t st_get_torrents(STSessionRef session, STTorrentStatus* out_items, int32_t max_items) {
    if (!session || !out_items || max_items <= 0) return 0;
    auto* w = (SessionWrap*)session;

    std::lock_guard<std::mutex> lock(w->mtx);

    std::vector<lt::torrent_handle> ts = w->sess.get_torrents();

    w->handles = ts;
    w->names.clear();
    w->ids.clear();

    int32_t count = 0;

    for (auto const& h : ts) {
        if (!h.is_valid()) continue;
        if (count >= max_items) break;

        lt::torrent_status st = h.status();

        STTorrentStatus out{};
        out.progress = st.progress;
        out.total_wanted = st.total_wanted;
        out.total_wanted_done = st.total_wanted_done;

        out.download_rate = st.download_rate;
        out.upload_rate = st.upload_rate;

        out.num_peers = st.num_peers;
        out.num_seeds = st.num_seeds;

        out.state = (int32_t)st.state;

        out.is_seeding = st.is_seeding;
        out.is_paused = (st.flags & lt::torrent_flags::paused) != lt::torrent_flags_t{};
        out.has_error = !st.errc.message().empty();

        out_items[count] = out;

        w->names.push_back(st.name);
        w->ids.push_back(to_hex_id(h));

        count++;
    }

    return count;
}

int32_t st_get_torrent_file_count(STSessionRef session, int32_t torrent_index) {
    auto s = reinterpret_cast<SessionWrap*>(session);
    if (!s) return 0;
    if (torrent_index < 0 || torrent_index >= (int)s->handles.size()) return 0;

    lt::torrent_handle h = s->handles[torrent_index];
    if (!h.is_valid()) return 0;

    auto ti = h.torrent_file();
    if (!ti) return 0;

    return (int32_t)ti->files().num_files();
}

bool st_get_torrent_file_info(
    STSessionRef session,
    int32_t torrent_index,
    int32_t file_index,
    const char** out_path,
    int64_t* out_size,
    int64_t* out_done
) {
    auto s = reinterpret_cast<SessionWrap*>(session);
    if (!s || !out_path || !out_size || !out_done) return false;
    if (torrent_index < 0 || torrent_index >= (int)s->handles.size()) return false;

    lt::torrent_handle h = s->handles[torrent_index];
    if (!h.is_valid()) return false;

    auto ti = h.torrent_file();
    if (!ti) return false;

    int num = ti->files().num_files();
    if (file_index < 0 || file_index >= num) return false;

    std::vector<std::int64_t> prog;
    h.file_progress(prog, lt::torrent_handle::piece_granularity);

    std::string p = std::string(ti->files().file_path(file_index));
    if (p.empty()) p = std::string(ti->files().file_name(file_index));
    if (p.empty()) p = "file-" + std::to_string(file_index);

    static thread_local std::string tl_path;
    tl_path = p;

    *out_path = tl_path.c_str();
    *out_size = (int64_t)ti->files().file_size(file_index);
    *out_done = (file_index < (int)prog.size()) ? (int64_t)prog[file_index] : 0;

    return true;
}

const char* st_get_torrent_name(STSessionRef session, int32_t index) {
    if (!session) return "";
    auto* w = (SessionWrap*)session;
    if (index < 0 || index >= (int32_t)w->names.size()) return "";
    return w->names[(size_t)index].c_str();
}

const char* st_get_torrent_id(STSessionRef session, int32_t index) {
    if (!session) return "";
    auto* w = (SessionWrap*)session;
    if (index < 0 || index >= (int32_t)w->ids.size()) return "";
    return w->ids[(size_t)index].c_str();
}

bool st_torrent_pause(STSessionRef session, const char* torrent_id_hex) {
    if (!session || !torrent_id_hex) return false;
    auto* w = (SessionWrap*)session;

    std::lock_guard<std::mutex> lock(w->mtx);
    lt::torrent_handle h = find_handle_by_id(w, torrent_id_hex);
    if (!h.is_valid()) return false;

    h.unset_flags(lt::torrent_flags::auto_managed);
    h.pause();
    return true;
}

bool st_torrent_resume(STSessionRef session, const char* torrent_id_hex) {
    if (!session || !torrent_id_hex) return false;
    auto* w = (SessionWrap*)session;

    std::lock_guard<std::mutex> lock(w->mtx);
    lt::torrent_handle h = find_handle_by_id(w, torrent_id_hex);
    if (!h.is_valid()) return false;

    h.unset_flags(lt::torrent_flags::auto_managed);
    h.resume();
    return true;
}

bool st_torrent_remove(STSessionRef session, const char* torrent_id_hex, bool delete_files) {
    if (!session || !torrent_id_hex) return false;
    auto* w = (SessionWrap*)session;

    std::lock_guard<std::mutex> lock(w->mtx);
    lt::torrent_handle h = find_handle_by_id(w, torrent_id_hex);
    if (!h.is_valid()) return false;

    lt::remove_flags_t flags = {};
    if (delete_files) flags |= lt::session::delete_files;

    w->sess.remove_torrent(h, flags);
    return true;
}

} // extern "C"
