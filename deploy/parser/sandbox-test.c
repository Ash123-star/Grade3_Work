#include <errno.h>
#include <linux/filter.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <unistd.h>

static int limited(int resource, rlim_t maximum) {
    struct rlimit value;
    return getrlimit(resource, &value) == 0 && value.rlim_cur <= maximum;
}

int main(void) {
    errno = 0;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd >= 0) {
        close(fd);
        return 1;
    }
    if (errno != EPERM) return 2;
    if (!limited(RLIMIT_CPU, 25) || !limited(RLIMIT_AS, 2UL * 1024 * 1024 * 1024)
        || !limited(RLIMIT_FSIZE, 64UL * 1024 * 1024) || !limited(RLIMIT_NOFILE, 128)) return 3;
    return 0;
}
