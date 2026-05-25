#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define APP_UID 10001
#define APP_GID 10001

static void fail(const char *msg) {
    fprintf(stderr, "%s failed: %s\n", msg, strerror(errno));
    exit(1);
}

int main(void) {
    // Disable buffering for stdout immediately
    setvbuf(stdout, NULL, _IONBF, 0);
    
    printf("[startup] uid=%d euid=%d gid=%d egid=%d\n",
           getuid(), geteuid(), getgid(), getegid());

    if (mkdir("/run/cap-demo", 0750) < 0 && errno != EEXIST) {
        fail("mkdir");
    }

    if (chown("/run/cap-demo", APP_UID, APP_GID) < 0) {
        fail("chown");
    }

    if (setgroups(0, NULL) < 0) {
        fail("setgroups");
    }

    if (setgid(APP_GID) < 0) {
        fail("setgid");
    }

    if (setuid(APP_UID) < 0) {
        fail("setuid");
    }

    printf("[after drop] uid=%d euid=%d gid=%d egid=%d\n",
           getuid(), geteuid(), getgid(), getegid());

    int fd = open("/run/cap-demo/app.log", O_CREAT | O_WRONLY | O_APPEND, 0640);
    if (fd < 0) {
        fail("open app.log");
    }

    dprintf(fd, "app started safely as uid=%d gid=%d\n", getuid(), getgid());
    close(fd);

    printf("app is running; inspect /run/cap-demo/app.log inside the container\n");
    sleep(300);

    return 0;
}
