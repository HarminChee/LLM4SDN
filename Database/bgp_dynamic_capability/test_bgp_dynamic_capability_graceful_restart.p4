// P4 Program for Dynamic BGP Graceful Restart and LLGR Capabilities
#include <core.p4>

header ethernet_t {
    mac_addr dstAddr;
    mac_addr srcAddr;
    bit<16>  etherType;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ipv4_addr srcAddr;
    ipv4_addr dstAddr;
}

header bgp_graceful_restart_t {
    bit<1> graceful_restart_enabled;  // 1 if Graceful Restart is enabled
    bit<32> restart_timer;            // Restart time for Graceful Restart
    bit<1> notification_enabled;      // 1 if notification support is enabled
    bit<32> llgr_stale_time;          // Long-Lived Graceful Restart stale time
    bit<1> dynamic_capability;        // 1 if dynamic capabilities are enabled
}

struct metadata_t {
    bgp_graceful_restart_t bgp_gr_info;
    bit<1> valid_session;  // Flag to check if the BGP session is valid
}

parser MyParser(packet_in pkt, out headers_t hdr, inout metadata_t meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition accept;
    }
}

control ingress {
    apply {
        // Check if Graceful Restart and LLGR capabilities are dynamically exchanged
        if (hdr.ipv4.isValid()) {
            if (meta.bgp_gr_info.dynamic_capability == 1) {
                // Validate Graceful Restart and LLGR settings
                if (meta.bgp_gr_info.graceful_restart_enabled == 1) {
                    if (meta.bgp_gr_info.restart_timer <= 123) {
                        if (meta.bgp_gr_info.notification_enabled == 1) {
                            // Session is valid if notification is enabled and restart timer is valid
                            meta.valid_session = 1;
                            forward();
                        } else {
                            // Drop if notification support is disabled
                            drop();
                        }
                    } else {
                        // Drop if restart timer exceeds the limit
                        drop();
                    }
                } else {
                    // Drop if Graceful Restart is disabled
                    drop();
                }
            } else {
                // Drop if dynamic capabilities are not enabled
                drop();
            }
        }
    }
}

control egress {
    apply {
        // Egress processing if needed
    }
}

control MyDeparser(packet_out pkt, in headers_t hdr) {
    apply {
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
    }
}

control MyVerifyChecksum(inout headers_t hdr) {
    apply { }
}

control MyComputeChecksum(inout headers_t hdr) {
    apply { }
}

V1Switch(MyParser(), MyVerifyChecksum(), ingress(), egress(), MyComputeChecksum(), MyDeparser()) main;
