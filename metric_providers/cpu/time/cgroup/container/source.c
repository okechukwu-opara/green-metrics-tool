#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#include <sys/time.h>
#include <time.h>
#include <string.h> // for strtok

typedef struct container_t { // struct is a specification and this static makes no sense here
    char path[BUFSIZ];
    char *id;
} container_t;

// All variables are made static, because we believe that this will
// keep them local in scope to the file and not make them persist in state
// between Threads.
// TODO: If this code ever gets multi-threaded please review this assumption to
// not pollute another threads state
static int user_id = 0;
static long int user_hz;
static unsigned int msleep_time=1000;
static container_t *containers = NULL;

static long int read_cpu_cgroup(char* filename) {
    long int cpu_usage = -1;
    FILE* fd = NULL;
    fd = fopen(filename, "r"); // check for general readability only once
    fscanf(fd, "usage_usec %ld", &cpu_usage);
    fclose(fd);
    return cpu_usage;
}

static int output_stats(container_t *containers, int length) {
    struct timeval now;
    gettimeofday(&now, NULL);

    for(int i=0; i<length; i++) {
        printf("%ld%06ld %ld %s\n", now.tv_sec, now.tv_usec, read_cpu_cgroup(containers[i].path), containers[i].id);
    }
    usleep(msleep_time*1000);

    return 1;
}

// TODO: better arguement parsing, atm it assumes first argument is msleep_time,
//       and rest are container ids with no real error checking
int main(int argc, char **argv) {

    int c;
    int length = 0;

    setvbuf(stdout, NULL, _IONBF, 0);
    user_hz = sysconf(_SC_CLK_TCK);
    user_id = getuid();

    while ((c = getopt (argc, argv, "i:s:h")) != -1) {
        switch (c) {
        case 'h':
            printf("Usage: %s [-i msleep_time] [-h]\n\n",argv[0]);
            printf("\t-h      : displays this help\n");
            printf("\t-s      : string of container IDs separated by comma\n");
            printf("\t-i      : specifies the milliseconds sleep time that will be slept between measurements\n\n");

            struct timespec res;
            double resolution;

            printf("\tEnvironment variables:\n");
            printf("\tUserHZ\t\t%ld\n", user_hz);
            clock_getres(CLOCK_REALTIME, &res);
            resolution = res.tv_sec + (((double)res.tv_nsec)/1.0e9);
            printf("\tSystemHZ\t%ld\n", (unsigned long)(1/resolution + 0.5));
            printf("\tCLOCKS_PER_SEC\t%ld\n", CLOCKS_PER_SEC);
            exit(0);
        case 'i':
            msleep_time = atoi(optarg);
            break;
        case 's':
            containers = malloc(sizeof(container_t));
            char *id = strtok(optarg,",");
            for (; id != NULL; id = strtok(NULL, ",")) {
                //printf("Token: %s\n", id);
                length++;
                containers = realloc(containers, length * sizeof(container_t));
                containers[length-1].id = id;
                sprintf(containers[length-1].path,
                    "/sys/fs/cgroup/user.slice/user-%d.slice/user@%d.service/user.slice/docker-%s.scope/cpu.stat",
                    user_id, user_id, id);

                FILE* fd = NULL;
                fd = fopen(containers[length-1].path, "r"); // check for general readability only once
                if ( fd == NULL) {
                        fprintf(stderr, "Error - file %s failed to open: errno: %d\n", containers[length-1].path, errno);
                        exit(1);
                }
                fclose(fd);
            }

            break;
        default:
            fprintf(stderr,"Unknown option %c\n",c);
            exit(-1);
        }
    }

    if(containers == NULL) {
        fprintf(stderr, "Please supply at least one container id with -s XXXX\n");
        exit(1);
    }

    while(1) {
        output_stats(containers, length);
    }

    free(containers); // since tools is only aborted by CTRL+C this is never called, but memory is freed on program end

    return 0;
}
