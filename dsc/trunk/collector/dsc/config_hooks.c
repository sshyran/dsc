#include <syslog.h>
#include <unistd.h>
#include <string.h>

int promisc_flag;
void Pcap_init(const char *device, int promisc);

int
open_interface(const char *interface)
{
        syslog(LOG_INFO, "Opening interface %s", interface);
        Pcap_init(interface, promisc_flag);
	return 1;
}

int
set_bpf_program(const char *s)
{
	extern char *bpf_program_str;
        syslog(LOG_INFO, "BPF program is: %s", s);
	bpf_program_str = strdup(s);
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
        if (chdir(dir) < 0)
		return 0;
	return 1;
}


int
add_dataset(const char *name, const char *layer,
        const char *firstname, const char *firstindexer,
        const char *secondname, const char *secondindexer,
        const char *filtername)
{
	syslog(LOG_INFO, "creating dataset %s", name);
	return 1;
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