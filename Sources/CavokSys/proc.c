#include "cavok_sys.h"

#include <bsm/libbsm.h>
#include <libproc.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>

int cavok_proc_count(void) {
    int bytes = proc_listallpids(NULL, 0);
    if (bytes <= 0) return 0;
    return bytes / (int)sizeof(pid_t);
}

int cavok_proc_pids(int32_t *pids, int capacity) {
    if (pids == NULL || capacity <= 0) return 0;
    int slots = cavok_proc_count();
    if (slots < 64) slots = 64;
    pid_t *listed = NULL;
    int got = 0;
    for (int attempt = 0; attempt < 6; attempt++) {
        pid_t *next = calloc((size_t)slots, sizeof(pid_t));
        if (next == NULL) {
            free(listed);
            return 0;
        }
        free(listed);
        listed = next;
        int bytes = proc_listallpids(listed, slots * (int)sizeof(pid_t));
        got = bytes > 0 ? bytes / (int)sizeof(pid_t) : 0;
        if (got < slots || slots > (1 << 20)) break;
        slots *= 2;
    }
    int copy = got > capacity ? capacity : got;
    for (int i = 0; i < copy; i++) pids[i] = (int32_t)listed[i];
    free(listed);
    return copy;
}

static void cavok_append(char *destination, int destination_len, const char *piece) {
    if (destination_len <= 0 || piece == NULL || piece[0] == '\0') return;
    size_t used = strlen(destination);
    if ((int)used >= destination_len - 2) return;
    size_t room = (size_t)destination_len - used - 2;
    size_t length = strlen(piece);
    if (length > room) length = room;
    memcpy(destination + used, piece, length);
    destination[used + length] = '\x1F';
    destination[used + length + 1] = '\0';
}

/// `KERN_PROCARGS2` is argc, the executable path, padding NULs, then the argument strings.
static void cavok_arguments(int32_t pid, char *command, int command_len) {
    int mib[3] = {CTL_KERN, KERN_PROCARGS2, pid};
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0 || size < sizeof(int)) return;
    char *buffer = calloc(1, size + 1);
    if (buffer == NULL) return;
    if (sysctl(mib, 3, buffer, &size, NULL, 0) != 0) {
        free(buffer);
        return;
    }
    int argc = 0;
    memcpy(&argc, buffer, sizeof(int));
    char *cursor = buffer + sizeof(int);
    char *end = buffer + size;
    while (cursor < end && *cursor != '\0') cursor++;
    while (cursor < end && *cursor == '\0') cursor++;
    command[0] = '\0';
    for (int i = 0; i < argc && cursor < end; i++) {
        cavok_append(command, command_len, cursor);
        cursor += strlen(cursor) + 1;
    }
    free(buffer);
}

int cavok_proc_read(int32_t pid, int32_t *ppid, uint64_t *start_sec, uint64_t *start_usec, char *command, int command_len) {
    if (ppid == NULL || start_sec == NULL || start_usec == NULL || command == NULL || command_len < 2) return -1;
    struct proc_bsdinfo info;
    int got = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, (int)sizeof(info));
    if (got != (int)sizeof(info)) return -1;
    *ppid = (int32_t)info.pbi_ppid;
    *start_sec = info.pbi_start_tvsec;
    *start_usec = info.pbi_start_tvusec;
    command[0] = '\0';
    cavok_arguments(pid, command, command_len);
    if (command[0] == '\0') {
        char path[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(pid, path, sizeof(path)) > 0) cavok_append(command, command_len, path);
    }
    return command[0] == '\0' ? -1 : 0;
}

int32_t cavok_pid_from_audit_token(const void *bytes, int length) {
    if (bytes == NULL || length < (int)sizeof(audit_token_t)) return -1;
    audit_token_t token;
    memcpy(&token, bytes, sizeof(token));
    return (int32_t)audit_token_to_pid(token);
}
