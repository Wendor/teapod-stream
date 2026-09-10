#ifndef XRAY_FFI_H
#define XRAY_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum XrayStatus {
  XRAY_STATUS_OK = 0,
  XRAY_STATUS_NULL_ARGUMENT = 1,
  XRAY_STATUS_INVALID_UTF8 = 2,
  XRAY_STATUS_CONFIG_ERROR = 3,
  XRAY_STATUS_CORE_NOT_LOADED = 4,
  XRAY_STATUS_RUNTIME_ERROR = 5,
  XRAY_STATUS_NO_PACKET = 6,
  XRAY_STATUS_BUFFER_TOO_SMALL = 7,
  XRAY_STATUS_TUN_ERROR = 8,
  XRAY_STATUS_INVALID_ARGUMENT = 9,
  XRAY_STATUS_PANIC = 255
} XrayStatus;

typedef struct XrayTunStats {
  /* Set to the writable allocation size before calling xray_tun_stats. ABI
   * major 1 accepts the original prefix through
   * tun_fd_write_batch_max_packets and never writes more than this size. */
  size_t struct_size;
  uint64_t inbound_packets;
  uint64_t outbound_packets;
  uint64_t dropped_packets;
  uint64_t inbound_dropped_packets;
  uint64_t outbound_dropped_packets;
  uint64_t tcp_stack_to_remote_bytes;
  uint64_t tcp_remote_written_bytes;
  uint64_t tcp_remote_read_bytes;
  uint64_t tcp_backpressure_events;
  uint64_t tcp_stack_to_remote_backpressure_events;
  uint64_t tcp_remote_to_stack_backpressure_events;
  uint64_t tcp_remote_write_batches;
  uint64_t tcp_remote_write_batch_messages;
  uint64_t tcp_remote_write_batch_max_messages;
  uint64_t tcp_remote_write_batch_max_bytes;
  uint64_t tcp_remote_write_wait_events;
  uint64_t tcp_remote_write_wait_ms_total;
  uint64_t tcp_remote_write_wait_ms_max;
  uint64_t tcp_remote_flush_wait_events;
  uint64_t tcp_remote_flush_wait_ms_total;
  uint64_t tcp_remote_flush_wait_ms_max;
  uint64_t tcp_pending_remote_bytes;
  uint64_t tcp_pending_remote_flows;
  uint64_t tcp_pending_remote_max_bytes;
  uint64_t tcp_pending_upload_bytes;
  uint64_t tcp_pending_upload_max_bytes;
  uint64_t tcp_pending_total_bytes;
  uint64_t tcp_remote_buffer_limit_bytes;
  uint64_t tcp_buffer_hard_limit_bytes;
  uint64_t tcp_remote_buffer_pressure_active;
  uint64_t tcp_remote_write_errors;
  uint64_t tcp_remote_closed_events;
  uint64_t tcp_remote_read_errors;
  uint64_t tcp_open_errors;
  uint64_t tcp_open_events;
  uint64_t tcp_open_duration_ms_total;
  uint64_t tcp_open_duration_ms_max;
  uint64_t tcp_first_byte_events;
  uint64_t tcp_first_byte_duration_ms_total;
  uint64_t tcp_first_byte_duration_ms_max;
  uint64_t tcp443_open_events;
  uint64_t tcp443_open_duration_ms_total;
  uint64_t tcp443_open_duration_ms_max;
  uint64_t tcp443_first_byte_events;
  uint64_t tcp443_first_byte_duration_ms_total;
  uint64_t tcp443_first_byte_duration_ms_max;
  uint64_t active_tcp_flows;
  uint64_t active_udp_flows;
  uint64_t udp_flow_limit;
  uint64_t udp_budget_drops;
  uint64_t udp_evicted_flows;
  uint64_t udp_channel_dropped_packets;
  uint64_t udp_remote_open_events;
  uint64_t udp_remote_udp443_open_events;
  uint64_t udp_remote_written_bytes;
  uint64_t udp_remote_read_bytes;
  uint64_t udp_open_errors;
  uint64_t udp_vision_udp443_rejections;
  uint64_t udp_remote_write_errors;
  uint64_t udp_remote_read_errors;
  uint64_t udp_remote_closed_events;
  uint64_t udp_quic_blocked_packets;
  uint64_t inbound_queue_depth;
  uint64_t outbound_queue_depth;
  uint64_t inbound_queue_max_packets;
  uint64_t outbound_queue_max_packets;
  uint64_t tun_fd_write_batches;
  uint64_t tun_fd_write_batch_packets;
  uint64_t tun_fd_write_batch_max_packets;
  uint64_t tun_fd_read_loop_exits;
  uint64_t tun_fd_write_loop_exits;
  uint64_t tun_fd_transient_io_errors;
} XrayTunStats;

typedef enum XrayTunFdPacketFormat {
  XRAY_TUN_FD_PACKET_FORMAT_RAW_IP = 0,
  XRAY_TUN_FD_PACKET_FORMAT_DARWIN_UTUN = 1
} XrayTunFdPacketFormat;

typedef enum XrayTunFdClosePolicy {
  XRAY_TUN_FD_CLOSE_POLICY_BORROWED = 0,
  XRAY_TUN_FD_CLOSE_POLICY_OWNED = 1
} XrayTunFdClosePolicy;

typedef enum XrayTunRuntimeProfile {
  XRAY_TUN_RUNTIME_PROFILE_DEFAULT = 0,
  XRAY_TUN_RUNTIME_PROFILE_MOBILE = 1,
  XRAY_TUN_RUNTIME_PROFILE_DESKTOP = 2,
  XRAY_TUN_RUNTIME_PROFILE_LOW_MEMORY = 3,
  XRAY_TUN_RUNTIME_PROFILE_THROUGHPUT = 4,
  XRAY_TUN_RUNTIME_PROFILE_MOBILE_PLUS = 5
} XrayTunRuntimeProfile;

typedef enum XrayDnsBootstrapMode {
  XRAY_DNS_BOOTSTRAP_MODE_SYSTEM = 0,
  XRAY_DNS_BOOTSTRAP_MODE_STATIC_ONLY = 1
} XrayDnsBootstrapMode;

typedef enum XrayTcpSlowFlowKind {
  XRAY_TCP_SLOW_FLOW_KIND_UNKNOWN = 0,
  XRAY_TCP_SLOW_FLOW_KIND_OPEN = 1,
  XRAY_TCP_SLOW_FLOW_KIND_FIRST_BYTE = 2
} XrayTcpSlowFlowKind;

typedef struct XrayTcpSlowFlowEvent {
  XrayTcpSlowFlowKind kind;
  uint64_t open_duration_ms;
  uint64_t first_byte_duration_ms;
} XrayTcpSlowFlowEvent;

typedef struct XrayTcpFlowSummaryEvent {
  uint64_t closed;
  uint64_t duration_ms;
  uint64_t open_duration_ms;
  uint64_t first_byte_duration_ms;
  uint64_t remote_read_bytes;
  uint64_t ms_to_64kib;
  uint64_t ms_to_128kib;
  uint64_t ms_to_256kib;
  uint64_t ms_to_512kib;
  uint64_t ms_to_1mib;
} XrayTcpFlowSummaryEvent;

typedef struct XrayTcpRemoteWriteSlowEvent {
  uint64_t duration_ms;
  uint64_t bytes;
  uint64_t messages;
} XrayTcpRemoteWriteSlowEvent;

typedef struct XrayTcpOpenErrorEvent {
  uint64_t reserved;
} XrayTcpOpenErrorEvent;

typedef struct XrayUdpSlowFlowEvent {
  uint64_t first_response_duration_ms;
  uint64_t written_bytes;
  uint64_t read_bytes;
} XrayUdpSlowFlowEvent;

typedef struct XrayUdpResponseGapEvent {
  uint64_t response_gap_duration_ms;
  uint64_t written_bytes;
  uint64_t read_bytes;
} XrayUdpResponseGapEvent;

typedef struct XrayUdpQuicBlockedEvent {
  uint64_t bytes;
} XrayUdpQuicBlockedEvent;

typedef struct XrayCoreHandle XrayCoreHandle;
typedef struct XrayError XrayError;
typedef int32_t (*XraySocketProtectCallback)(int32_t fd, void *user_data);

/* Capability bits are additive within one ABI major. Preserve and ignore
 * unknown bits so a newer library remains usable through its older surface. */
typedef enum XrayFfiCapability {
  XRAY_FFI_CAPABILITY_CONFIG_WARNINGS = 1 << 0,
  XRAY_FFI_CAPABILITY_GEODATA_SEARCH = 1 << 1,
  XRAY_FFI_CAPABILITY_SOCKET_PROTECTION = 1 << 2,
  XRAY_FFI_CAPABILITY_STARTUP_PROBE = 1 << 3,
  XRAY_FFI_CAPABILITY_FILE_LOGGING = 1 << 4,
  XRAY_FFI_CAPABILITY_TUN_PACKET_IO = 1 << 5,
  XRAY_FFI_CAPABILITY_TUN_FD = 1 << 6,
  XRAY_FFI_CAPABILITY_TUN_BATCH_POLL = 1 << 7,
  XRAY_FFI_CAPABILITY_TUN_RUNTIME_PROFILES = 1 << 8,
  XRAY_FFI_CAPABILITY_DNS_BOOTSTRAP_POLICY = 1 << 9,
  XRAY_FFI_CAPABILITY_TUN_STATS = 1 << 10,
  XRAY_FFI_CAPABILITY_TUN_DIAGNOSTIC_EVENTS = 1 << 11,
  XRAY_FFI_CAPABILITY_OUTBOUND_SELECTION = 1 << 12,
  XRAY_FFI_CAPABILITY_OUTBOUND_HEALTH = 1 << 13,
  XRAY_FFI_CAPABILITY_CONNECTION_MANAGEMENT = 1 << 14,
  XRAY_FFI_CAPABILITY_ROUTING_POLICY_UPDATE = 1 << 15
} XrayFfiCapability;

uint32_t xray_ffi_version_major(void);
uint32_t xray_ffi_version_minor(void);
uint64_t xray_ffi_capabilities(void);

XrayCoreHandle *xray_core_new(XrayError **error);
/* Searches dir first, then the process default geodata directories. */
XrayStatus xray_core_set_geodata_search_dir(
    XrayCoreHandle *handle,
    const char *dir,
    XrayError **error);
/* Searches only dir; missing referenced assets fail config loading. */
XrayStatus xray_core_set_geodata_search_dir_exclusive(
    XrayCoreHandle *handle,
    const char *dir,
    XrayError **error);
/* A handle accepts exactly one successful full-config load. Create a new
 * handle to replace the full configuration; routing policy alone has the
 * scoped live-update call below. */
XrayStatus xray_core_load_config_json(
    XrayCoreHandle *handle,
    const char *json,
    XrayError **error);
/* Copies diagnostics from the most recent successful config load. `written`
 * receives the UTF-8 byte length excluding the trailing NUL. Pass NULL/0 as
 * buffer/buffer_len to query the required length. */
XrayStatus xray_core_config_warnings(
    const XrayCoreHandle *handle,
    char *buffer,
    size_t buffer_len,
    size_t *written,
    XrayError **error);
XrayStatus xray_core_start(XrayCoreHandle *handle, XrayError **error);
XrayStatus xray_core_stop(XrayCoreHandle *handle, XrayError **error);
/* Selector overrides affect new flows only and may be changed while running. */
XrayStatus xray_core_set_outbound_selector_override(
    XrayCoreHandle *handle,
    const char *group_tag,
    const char *outbound_tag,
    XrayError **error);
XrayStatus xray_core_clear_outbound_selector_override(
    XrayCoreHandle *handle,
    const char *group_tag,
    XrayError **error);
/* Replaces routing rules and compiled geodata matchers for new flows. `json`
 * must contain exactly one top-level routing object. Balancer topology remains
 * immutable; create a new core handle to change it. */
XrayStatus xray_core_replace_routing_policy_json(
    XrayCoreHandle *handle,
    const char *json,
    XrayError **error);
/* Snapshot documents use schemaVersion 1. `written` excludes the trailing NUL;
 * pass NULL/0 as buffer/buffer_len to query the required UTF-8 byte length. */
XrayStatus xray_core_outbound_selection_snapshot_json(
    const XrayCoreHandle *handle,
    char *buffer,
    size_t buffer_len,
    size_t *written,
    XrayError **error);
XrayStatus xray_core_routing_policy_snapshot_json(
    const XrayCoreHandle *handle,
    char *buffer,
    size_t buffer_len,
    size_t *written,
    XrayError **error);
XrayStatus xray_core_outbound_health_snapshot_json(
    const XrayCoreHandle *handle,
    char *buffer,
    size_t buffer_len,
    size_t *written,
    XrayError **error);
XrayStatus xray_core_connection_snapshot_json(
    const XrayCoreHandle *handle,
    char *buffer,
    size_t buffer_len,
    size_t *written,
    XrayError **error);
XrayStatus xray_core_outbound_accounting_snapshot_json(
    const XrayCoreHandle *handle,
    char *buffer,
    size_t buffer_len,
    size_t *written,
    XrayError **error);
XrayStatus xray_core_close_connection(
    XrayCoreHandle *handle,
    uint64_t connection_id,
    XrayError **error);
XrayStatus xray_core_set_socket_protect_callback(
    XrayCoreHandle *handle,
    XraySocketProtectCallback callback,
    void *user_data,
    XrayError **error);
XrayStatus xray_core_set_file_logging(
    XrayCoreHandle *handle,
    const char *log_dir,
    int32_t enabled,
    XrayError **error);
XrayStatus xray_core_set_startup_probe(
    XrayCoreHandle *handle,
    const char *url,
    uint64_t timeout_ms,
    const char *outbound_tag,
    XrayError **error);
/* Reconfiguring the same numeric fd transfers packet format and close policy
 * without closing it. Replacing it with a different fd closes the old fd when
 * its previous policy was XRAY_TUN_FD_CLOSE_POLICY_OWNED. */
XrayStatus xray_core_set_tun_fd(
    XrayCoreHandle *handle,
    int32_t fd,
    int32_t packet_format,
    int32_t close_policy,
    XrayError **error);
XrayStatus xray_core_set_tun_collect_tcp_timings(
    XrayCoreHandle *handle,
    int32_t collect_tcp_timings,
    XrayError **error);
XrayStatus xray_core_set_tun_runtime_profile(
    XrayCoreHandle *handle,
    int32_t profile,
    XrayError **error);
/* Defaults to XRAY_DNS_BOOTSTRAP_MODE_SYSTEM. Set before config load; tunnel
 * integrations may select STATIC_ONLY after completing host-side bootstrap. */
XrayStatus xray_core_set_dns_bootstrap_mode(
    XrayCoreHandle *handle,
    int32_t mode,
    XrayError **error);
void xray_core_free(XrayCoreHandle *handle);

XrayStatus xray_error_code(const XrayError *error);
const char *xray_error_message(const XrayError *error);
void xray_error_free(XrayError *error);

XrayStatus xray_tun_push_packet(
    XrayCoreHandle *handle,
    const uint8_t *data,
    size_t len,
    XrayError **error);
/* On XRAY_STATUS_BUFFER_TOO_SMALL, *written receives the required packet
 * length and the packet is retained for the next xray_tun_poll_packet call. */
XrayStatus xray_tun_poll_packet(
    XrayCoreHandle *handle,
    uint8_t *buffer,
    size_t buffer_len,
    size_t *written,
    XrayError **error);
/* Blocks up to wait_ms for the first packet (0 polls without waiting), then
 * drains ready packets back-to-back into buffer; packet_lengths[i] receives
 * each length and *packet_count the number written. At most
 * min(max_packets, buffer_len / mtu) packets are returned per call.
 * May be called concurrently with xray_tun_push_packet / xray_tun_poll_packet
 * / xray_tun_stats on the same handle, but never concurrently with lifecycle
 * calls (load_config / start / stop / set_* / free). */
XrayStatus xray_tun_poll_packets(
    XrayCoreHandle *handle,
    uint8_t *buffer,
    size_t buffer_len,
    size_t *packet_lengths,
    size_t max_packets,
    size_t *packet_count,
    uint32_t wait_ms,
    XrayError **error);
XrayStatus xray_tun_poll_tcp_slow_flow_event(
    XrayCoreHandle *handle,
    XrayTcpSlowFlowEvent *event,
    char *target_buffer,
    size_t target_buffer_len,
    size_t *target_written,
    XrayError **error);
XrayStatus xray_tun_poll_tcp_flow_summary_event(
    XrayCoreHandle *handle,
    XrayTcpFlowSummaryEvent *event,
    char *target_buffer,
    size_t target_buffer_len,
    size_t *target_written,
    char *outbound_tag_buffer,
    size_t outbound_tag_buffer_len,
    size_t *outbound_tag_written,
    XrayError **error);
XrayStatus xray_tun_poll_tcp_remote_write_slow_event(
    XrayCoreHandle *handle,
    XrayTcpRemoteWriteSlowEvent *event,
    char *target_buffer,
    size_t target_buffer_len,
    size_t *target_written,
    char *outbound_tag_buffer,
    size_t outbound_tag_buffer_len,
    size_t *outbound_tag_written,
    XrayError **error);
XrayStatus xray_tun_poll_tcp_open_error_event(
    XrayCoreHandle *handle,
    XrayTcpOpenErrorEvent *event,
    char *target_buffer,
    size_t target_buffer_len,
    size_t *target_written,
    char *outbound_tag_buffer,
    size_t outbound_tag_buffer_len,
    size_t *outbound_tag_written,
    char *error_message_buffer,
    size_t error_message_buffer_len,
    size_t *error_message_written,
    XrayError **error);
XrayStatus xray_tun_poll_udp_slow_flow_event(
    XrayCoreHandle *handle,
    XrayUdpSlowFlowEvent *event,
    char *target_buffer,
    size_t target_buffer_len,
    size_t *target_written,
    XrayError **error);
XrayStatus xray_tun_poll_udp_response_gap_event(
    XrayCoreHandle *handle,
    XrayUdpResponseGapEvent *event,
    char *target_buffer,
    size_t target_buffer_len,
    size_t *target_written,
    XrayError **error);
XrayStatus xray_tun_poll_udp_quic_blocked_event(
    XrayCoreHandle *handle,
    XrayUdpQuicBlockedEvent *event,
    char *target_buffer,
    size_t target_buffer_len,
    size_t *target_written,
    XrayError **error);
/* Writes at most min(stats->struct_size, sizeof(XrayTunStats)) bytes. */
XrayStatus xray_tun_stats(
    XrayCoreHandle *handle,
    XrayTunStats *stats,
    XrayError **error);

#ifdef __cplusplus
}
#endif

#endif
