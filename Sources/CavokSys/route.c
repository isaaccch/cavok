#include "cavok_sys.h"

#include <arpa/inet.h>
#include <errno.h>
#include <net/if.h>
#include <net/route.h>
#include <netinet/in.h>
#include <stdatomic.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

// A flap can deliver a burst of RTM_IFINFO and RTM_NEWADDR before our RTM_GET reply.
// Those messages are skipped. The cap only stops a flood; the socket timeout stops a quiet socket.
#define CAVOK_ROUTE_SKIP_CAP 256

bool cavok_route_socket_ok(void) {
    int fd = socket(PF_ROUTE, SOCK_RAW, 0);
    if (fd < 0) return false;
    close(fd);
    return true;
}

int cavok_route_interface(const char *address, char *name, int name_len) {
    // if_indextoname writes IF_NAMESIZE bytes and does not take a length.
    if (address == NULL || name == NULL || name_len < IF_NAMESIZE) return -1;
    name[0] = '\0';

    struct sockaddr_storage destination;
    memset(&destination, 0, sizeof(destination));
    if (strchr(address, ':') != NULL) {
        struct sockaddr_in6 *v6 = (struct sockaddr_in6 *)&destination;
        v6->sin6_len = sizeof(*v6);
        v6->sin6_family = AF_INET6;
        if (inet_pton(AF_INET6, address, &v6->sin6_addr) != 1) return -1;
    } else {
        struct sockaddr_in *v4 = (struct sockaddr_in *)&destination;
        v4->sin_len = sizeof(*v4);
        v4->sin_family = AF_INET;
        if (inet_pton(AF_INET, address, &v4->sin_addr) != 1) return -1;
    }

    int fd = socket(PF_ROUTE, SOCK_RAW, 0);
    if (fd < 0) return -1;
    struct timeval timeout = {.tv_sec = 1, .tv_usec = 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    unsigned char request[512];
    memset(request, 0, sizeof(request));
    struct rt_msghdr *header = (struct rt_msghdr *)request;
    socklen_t address_len = destination.ss_len;
    if (sizeof(struct rt_msghdr) + address_len > sizeof(request)) {
        close(fd);
        return -1;
    }
    memcpy(request + sizeof(struct rt_msghdr), &destination, address_len);
    static atomic_uint_least32_t sequence = 1;
    uint32_t seq = atomic_fetch_add_explicit(&sequence, 1, memory_order_relaxed);
    header->rtm_msglen = (u_short)(sizeof(struct rt_msghdr) + address_len);
    header->rtm_version = RTM_VERSION;
    header->rtm_type = RTM_GET;
    header->rtm_addrs = RTA_DST;
    header->rtm_seq = (int)seq;
    header->rtm_pid = getpid();
    header->rtm_flags = RTF_UP;

    if (write(fd, request, header->rtm_msglen) < 0) {
        close(fd);
        return -1;
    }

    unsigned char reply[2048];
    int found = 0;
    int skipped = 0;
    while (skipped < CAVOK_ROUTE_SKIP_CAP) {
        ssize_t got = read(fd, reply, sizeof(reply));
        if (got < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (got < (ssize_t)sizeof(struct rt_msghdr)) break;
        struct rt_msghdr *answer = (struct rt_msghdr *)reply;
        if (answer->rtm_type != RTM_GET || answer->rtm_seq != (int)seq || answer->rtm_pid != getpid()) {
            skipped++;
            continue;
        }
        if (answer->rtm_errno != 0) break;
        if (answer->rtm_index != 0 && if_indextoname(answer->rtm_index, name) != NULL && name[0] != '\0') {
            found = 1;
        }
        break;
    }
    close(fd);
    return found ? 0 : -1;
}
