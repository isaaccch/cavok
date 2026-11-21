#ifndef CAVOK_SYS_H
#define CAVOK_SYS_H

#include <stdbool.h>
#include <stdint.h>

/// 0 on success. The name is the interface for this destination, the same answer as `route -n get`.
int cavok_route_interface(const char *address, char *name, int name_len);

/// True when a routing socket can be opened.
bool cavok_route_socket_ok(void);

/// Reads one process. `command` is the executable and its arguments, each followed by U+001F
/// (0x1F). The trailing separator keeps a path that contains a space one token.
int cavok_proc_read(int32_t pid, int32_t *ppid, uint64_t *start_sec, uint64_t *start_usec, char *command, int command_len);

/// Writes up to `capacity` pids. Returns how many were written.
/// A return equal to `capacity` means the buffer was full and the caller should grow it.
/// The list itself is reread until it fits, or until a few doublings have been tried.
int cavok_proc_pids(int32_t *pids, int capacity);

/// How many pids a following call should allocate for.
int cavok_proc_count(void);

/// pid inside an audit token blob, or -1.
int32_t cavok_pid_from_audit_token(const void *bytes, int length);

#endif
