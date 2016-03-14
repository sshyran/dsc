#include <stdio.h>
#include <syslog.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include "xmalloc.h"
#include "dns_message.h"
#include "syslog_debug.h"
#include "hashtbl.h"

int promisc_flag;
#if HAVE_LIBNCAP
void Ncap_init(const char *device, int promisc);
#endif
void Pcap_init(const char *device, int promisc);
uint64_t minfree_bytes = 0;
int output_format_xml = 0;
int output_format_json = 0;
#define MAX_HASH_SIZE 512
static hashtbl * dataset_hash = NULL;

int
open_interface(const char *interface)
{
    syslog(LOG_INFO, "Opening interface %s", interface);
#if HAVE_LIBNCAP
    Ncap_init(interface, promisc_flag);
#else
    Pcap_init(interface, promisc_flag);
#endif
    return 1;
}

int
set_bpf_program(const char *s)
{
    extern char *bpf_program_str;
    syslog(LOG_INFO, "BPF program is: %s", s);
    bpf_program_str = xstrdup(s);
    if (NULL == bpf_program_str)
	return 0;
    return 1;
}

int
add_local_address(const char *s)
{
    extern int ip_local_address(const char *);
    syslog(LOG_INFO, "adding local address %s", s);
    return ip_local_address(s);
}

int
set_run_dir(const char *dir)
{
    syslog(LOG_INFO, "setting current directory to %s", dir);
    if (chdir(dir) < 0) {
	perror(dir);
	syslog(LOG_ERR, "chdir: %s: %s", dir, strerror(errno));
	return 0;
    }
    return 1;
}

int
set_pid_file(const char *s)
{
    extern char *pid_file_name;
    syslog(LOG_INFO, "PID file is: %s", s);
    pid_file_name = xstrdup(s);
    if (NULL == pid_file_name)
	return 0;
    return 1;
}

static unsigned int
dataset_hashfunc(const void *key)
{
    return hashendian(key, strlen(key), 0);
}

static int
dataset_cmpfunc(const void *a, const void *b)
{
    return strcasecmp(a, b);
}
int
add_dataset(const char *name, const char *layer_ignored,
    const char *firstname, const char *firstindexer,
    const char *secondname, const char *secondindexer, const char *filtername, dataset_opt opts)
{
    char * dup;

    if ( !dataset_hash ) {
        if ( !(dataset_hash = hash_create(MAX_HASH_SIZE, dataset_hashfunc, dataset_cmpfunc, 0, afree, afree)) ) {
            syslog(LOG_ERR, "unable to create dataset %s due to internal error", name);
            return 0;
        }
    }

    if ( hash_find(name, dataset_hash) ) {
        syslog(LOG_ERR, "unable to create dataset %s: already exists", name);
        return 0;
    }

    if ( !(dup = xstrdup(name)) ) {
        syslog(LOG_ERR, "unable to create dataset %s due to internal error", name);
        return 0;
    }

    if ( hash_add(dup, dup, dataset_hash) ) {
        afree(dup);
        syslog(LOG_ERR, "unable to create dataset %s due to internal error", name);
        return 0;
    }

    syslog(LOG_INFO, "creating dataset %s", name);
    return dns_message_add_array(name, firstname, firstindexer, secondname, secondindexer, filtername, opts);
}

int
set_bpf_vlan_tag_byte_order(const char *which)
{
    extern int vlan_tag_needs_byte_conversion;
    syslog(LOG_INFO, "bpf_vlan_tag_byte_order is %s", which);
    if (0 == strcmp(which, "host")) {
	vlan_tag_needs_byte_conversion = 0;
	return 1;
    }
    if (0 == strcmp(which, "net")) {
	vlan_tag_needs_byte_conversion = 1;
	return 1;
    }
    syslog(LOG_ERR, "unknown bpf_vlan_tag_byte_order '%s'", which);
    return 0;
}

int
set_match_vlan(const char *s)
{
    extern void pcap_set_match_vlan(int);
    int i;
    syslog(LOG_INFO, "match_vlan %s", s);
    i = atoi(s);
    if (0 == i && 0 != strcmp(s, "0"))
	return 0;
    pcap_set_match_vlan(i);
    return 1;
}

int
set_minfree_bytes(const char *s)
{
    syslog(LOG_INFO, "minfree_bytes %s", s);
    minfree_bytes = strtoull(s, NULL, 10);
    return 1;
}

int
set_output_format(const char *output_format)
{
    syslog(LOG_INFO, "output_format %s", output_format);

    if ( !strcmp(output_format, "XML") ) {
        output_format_xml = 1;
        return 1;
    }
    else if ( !strcmp(output_format, "JSON") ) {
        output_format_json = 1;
        return 1;
    }

    syslog(LOG_ERR, "unknown output format '%s'", output_format);
    return 0;
}