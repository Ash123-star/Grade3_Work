#define _GNU_SOURCE
#include <errno.h>
#include <stddef.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>

/* 无提权的每文件沙箱：网络系统调用由内核拒绝，限额随 exec 继承。 */
#if defined(__x86_64__)
#define PARSER_ARCH AUDIT_ARCH_X86_64
#elif defined(__aarch64__)
#define PARSER_ARCH AUDIT_ARCH_AARCH64
#else
#error Unsupported parser architecture
#endif
#define DENY(call) BPF_JUMP(BPF_JMP+BPF_JEQ+BPF_K, __NR_##call, 0, 1), BPF_STMT(BPF_RET+BPF_K, SECCOMP_RET_ERRNO | EPERM)
static int limit(int resource, rlim_t value) {
    struct rlimit bound = {value, value};
    return setrlimit(resource, &bound);
}
int main(int argc, char **argv) {
    if (argc < 2 || limit(RLIMIT_CPU, 25) || limit(RLIMIT_AS, 2ULL*1024*1024*1024)
        || limit(RLIMIT_FSIZE, 64ULL*1024*1024) || limit(RLIMIT_NOFILE, 128)
        || limit(RLIMIT_CORE, 0)) return 125;
    struct sock_filter rules[] = {
        BPF_STMT(BPF_LD+BPF_W+BPF_ABS, offsetof(struct seccomp_data, arch)),
        BPF_JUMP(BPF_JMP+BPF_JEQ+BPF_K, PARSER_ARCH, 1, 0),
        BPF_STMT(BPF_RET+BPF_K, SECCOMP_RET_KILL_PROCESS),
        BPF_STMT(BPF_LD+BPF_W+BPF_ABS, offsetof(struct seccomp_data, nr)),
        DENY(socket), DENY(socketpair), DENY(connect), DENY(bind), DENY(listen),
        DENY(accept), DENY(accept4), DENY(sendto), DENY(sendmsg), DENY(recvfrom),
        DENY(recvmsg), DENY(ptrace), DENY(mount), DENY(unshare), DENY(setns),
        BPF_STMT(BPF_RET+BPF_K, SECCOMP_RET_ALLOW)
    };
    struct sock_fprog program = {sizeof(rules)/sizeof(rules[0]), rules};
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) || prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program)) return 125;
    execv(argv[1], &argv[1]);
    return 125;
}
