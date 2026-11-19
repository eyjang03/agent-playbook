/* Prints the pids of this user's processes that belong to one reviewer's sandbox: sandboxed, allowed to write the
   reviewer's tmp folder, NOT allowed to write the audit folder above it (which excludes system services whose own
   sandboxes allow writing anywhere under /tmp), and started at or after <start epoch>. Only reports; never signals.
   Exit 0: the list is complete. Exit 3: a live candidate could not be classified (the scan is inconclusive).
   Usage: boxcheck <reviewer tmp folder> <audit folder> <start epoch> */
#include <errno.h>
#include <signal.h>
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>

enum { SANDBOX_FILTER_PATH = 1, SANDBOX_CHECK_NO_REPORT = 0x40000000 };
int sandbox_check(pid_t pid, const char *operation, int type, ...);
int main(int argc, char **argv) {
    if (argc != 4) { fprintf(stderr, "usage: boxcheck <reviewer tmp folder> <audit folder> <start epoch>\n"); return 2; }
    long since = atol(argv[3]);
    int n = proc_listallpids(NULL, 0); if (n <= 0) return 1;
    pid_t *pids = calloc((size_t)n + 64, sizeof(pid_t));
    if (!pids) return 1;
    n = proc_listallpids(pids, (int)((n + 64) * sizeof(pid_t))); if (n <= 0) return 1;
    uid_t me = getuid(); int unknown = 0;
    for (int i = 0; i < n; i++) {
        struct proc_bsdinfo info;
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &info, sizeof info) != sizeof info) {
            /* details refused (for example a root-owned login process of this user's terminal): the kernel's process
               table still gives owner, start time and state; only a live process of this user that started during
               the attempt and still cannot be read leaves ownership unknown */
            struct kinfo_proc kp; size_t len = sizeof kp; int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pids[i]};
            if (pids[i] > 1 && sysctl(mib, 4, &kp, &len, NULL, 0) == 0 && len == sizeof kp && kp.kp_proc.p_stat != SZOMB
                && (kp.kp_eproc.e_ucred.cr_uid == me || kp.kp_eproc.e_pcred.p_ruid == me)
                && (long)kp.kp_proc.p_starttime.tv_sec >= since) unknown++;
            continue;   /* exited, another user's, or older than this attempt */
        }
        if (info.pbi_uid != me || (long)info.pbi_start_tvsec < since) continue;
        /* an error (-1) for a process that is still alive leaves its ownership unknown: never silently skipped */
        int sb = sandbox_check(pids[i], NULL, 0);
        int wt = sb == 1 ? sandbox_check(pids[i], "file-write-data", SANDBOX_FILTER_PATH | SANDBOX_CHECK_NO_REPORT, argv[1]) : 1;
        int wa = (sb == 1 && wt == 0) ? sandbox_check(pids[i], "file-write-data", SANDBOX_FILTER_PATH | SANDBOX_CHECK_NO_REPORT, argv[2]) : 1;
        if (sb == -1 || wt == -1 || wa == -1) { if (kill(pids[i], 0) == 0 || errno == EPERM) unknown++; continue; }
        if (sb == 1 && wt == 0 && wa == 1) printf("%d\n", pids[i]);   /* sandboxed, may write tmp, may not write the audit folder */
    }
    return unknown ? 3 : 0;
}
