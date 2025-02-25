// P4 Program for BGP Confederation with Internal and External Peers
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

header bgp_confed_t {
    bit<16> confed_id;   // Confederation ID
    bit<16> as_number;   // AS number
    bit<1>  is_internal; // 1 if internal peer, 0 if external peer
}

struct metadata_t {
    bgp_confed_t bgp_confed_info;
    bit<1> valid_route;  // Flag to check if the route is valid
    bit<1> internal_peer;  // 1 if it's an internal peer
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
        if (hdr.ipv4.isValid()) {
            // Confederation ID and AS number checks
            if (meta.bgp_confed_info.confed_id == 65001) {
                // If the packet is part of the confederation
                if (meta.bgp_confed_info.as_number == 65002) {
                    // If internal, allow the route
                    meta.internal_peer = 1;
                    meta.valid_route = 1;
                    forward();
                } else if (meta.bgp_confed_info.as_number == 65003) {
                    // If external (but still within the confederation), allow the route
                    meta.internal_peer = 0;
                    meta.valid_route = 1;
                    forward();
                } else {
                    // Invalid AS number, drop the packet
                    meta.valid_route = 0;
                    drop();
                }
            } else {
                // If it's an external route (outside the confederation), drop it
                drop();
            }
        }
    }
}

control egress {
    apply {
        // Egress processing, if needed
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
