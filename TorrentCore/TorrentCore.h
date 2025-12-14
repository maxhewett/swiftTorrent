//
//  TorrentCore.h
//  TorrentCore
//
//  Created by Max Hewett on 14/12/2025.
//

// TorrentCore.h
#pragma once

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* STSessionRef;

typedef struct {
    float    progress;        // 0.0 -> 1.0
    int64_t  total_wanted;     // bytes
    int64_t  total_wanted_done;

    int32_t  download_rate;    // bytes/sec
    int32_t  upload_rate;      // bytes/sec

    int32_t  num_peers;
    int32_t  num_seeds;
    
    int32_t  state; // libtorrent torrent_status::state_t

    bool     is_seeding;
    bool     is_paused;
    bool     has_error;
} STTorrentStatus;

STSessionRef st_session_create(uint16_t listen_port_start, uint16_t listen_port_end);
void st_session_destroy(STSessionRef session);

bool st_add_magnet(
    STSessionRef session,
    const char* magnet_uri,
    const char* save_path,
    char* err_buf,
    int32_t err_buf_len
);

// Caller provides out_items[max_items]. Returns number written.
int32_t st_get_torrents(STSessionRef session, STTorrentStatus* out_items, int32_t max_items);

// After calling st_get_torrents(), you can retrieve the torrent name for an index [0..<count]
const char* st_get_torrent_name(STSessionRef session, int32_t index);

#ifdef __cplusplus
}
#endif
