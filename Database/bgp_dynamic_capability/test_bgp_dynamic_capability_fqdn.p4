// P4 Program for Dynamic BGP FQDN Capability Exchange
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

header bgp_fqdn_t {
    bit<1> fqdn_enabled;      // 1 if FQDN capability is enabled
    bit<128> advHostName;     // Local advertised hostname
    bit<128> rcvHostName;     // Received hostname from peer
    bit<1> dynamic_capability;  // 1 if dynamic capabilities are enabled
}

struct metadata_t {
    bgp_fqdn_t bgp_fqdn_info;
    bit<1> valid_session;      // Flag to check if the BGP session is valid
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
        // Check if the FQDN capability is dynamically exchanged
        if (hdr.ipv4.isValid()) {
            if (meta.bgp_fqdn_info.dynamic_capability == 1) {
                // If dynamic capabilities are enabled, validate the FQDN exchange
                if (meta.bgp_fqdn_info.fqdn_enabled == 1) {
                    // FQDN capability is enabled, session is valid
                    meta.valid_session = 1;
                    forward();
                } else {
                    // Drop if FQDN capability is disabled
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
