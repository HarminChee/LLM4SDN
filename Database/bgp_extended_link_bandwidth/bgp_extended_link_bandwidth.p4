// P4 Program for BGP Extended Communities with Link Bandwidth
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

header bgp_extended_community_t {
    bit<1> lb_enabled;      // 1 if Link Bandwidth (LB) is present
    bit<64> lb_value;       // Link Bandwidth value in bits per second
}

struct metadata_t {
    bgp_extended_community_t ext_comm;
    bit<1> valid_route;     // Flag to check if the route is valid
    bit<1> ebgp_session;    // 1 if the session is eBGP, 0 if iBGP
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
        // Check if the link bandwidth extended community is enabled
        if (meta.ext_comm.lb_enabled == 1) {
            if (meta.ebgp_session == 1) {
                // If it's an eBGP session, remove the non-transitive link bandwidth community
                meta.ext_comm.lb_enabled = 0;
            }
        }

        // Forward the packet if the route is valid
        if (meta.valid_route == 1) {
            forward();
        } else {
            drop();
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
