// P4 Program for BGP IPv6 Nexthop Propagation
#include <core.p4>

header ethernet_t {
    mac_addr dstAddr;
    mac_addr srcAddr;
    bit<16> etherType;
}

header ipv6_t {
    bit<4> version;
    bit<8> trafficClass;
    bit<20> flowLabel;
    bit<16> payloadLen;
    bit<8> nextHdr;
    bit<8> hopLimit;
    ipv6_addr srcAddr;
    ipv6_addr dstAddr;
}

header bgp_t {
    bit<16> as_number;         // Autonomous System number
    ipv6_addr advertised_prefix; // Advertised IPv6 prefix
    ipv6_addr nexthop;         // BGP nexthop (IPv6)
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;         // Flag to check if the BGP route is valid
    bit<1> nexthop_valid;       // Flag to check if the nexthop is valid
}

parser MyParser(packet_in pkt, out headers_t hdr, inout metadata_t meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x86DD: parse_ipv6; // IPv6
            default: accept;
        }
    }

    state parse_ipv6 {
        pkt.extract(hdr.ipv6);
        transition accept;
    }
}

control ingress {
    apply {
        // Check if the advertised prefix is valid
        if (meta.bgp_info.advertised_prefix != 0) {
            meta.valid_route = 1;
        }

        // Check if the nexthop is valid (non-link-local)
        if (meta.bgp_info.nexthop != 0) {
            meta.nexthop_valid = 1;
        } else {
            meta.nexthop_valid = 0;
        }

        // Forward the route if the BGP route and nexthop are valid
        if (meta.valid_route == 1 && meta.nexthop_valid == 1) {
            forward();
        } else {
            drop(); // Drop the packet if the route or nexthop is not valid
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
        pkt.emit(hdr.ipv6);
    }
}

control MyVerifyChecksum(inout headers_t hdr) {
    apply { }
}

control MyComputeChecksum(inout headers_t hdr) {
    apply { }
}

V1Switch(MyParser(), MyVerifyChecksum(), ingress(), egress(), MyComputeChecksum(), MyDeparser()) main;
