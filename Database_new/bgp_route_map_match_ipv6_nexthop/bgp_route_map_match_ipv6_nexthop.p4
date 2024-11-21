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
    ipv6_addr next_hop;         // Next-hop IPv6 address
    ipv6_addr prefix;           // Advertised prefix
    bit<16> community;          // Community attribute
    bit<1> valid;               // Valid route flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;         // Indicates whether the route is valid
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
        // Default route validity
        meta.valid_route = 0;

        // Match routes by IPv6 next-hop and assign community tags
        if (meta.bgp_info.next_hop == 0x20010DB800010002) { // IPv6 next-hop: 2001:db8:1::2
            if (meta.bgp_info.prefix == 0x20010DB800010001) {
                meta.bgp_info.community = 0x65002; // Community: 65002:1
                meta.valid_route = 1;
            } else if (meta.bgp_info.prefix == 0x20010DB800020001) {
                meta.bgp_info.community = 0x65002; // Community: 65002:2
                meta.valid_route = 1;
            } else if (meta.bgp_info.prefix == 0x20010DB800030001) {
                meta.bgp_info.community = 0x65002; // Community: 65002:3
                meta.valid_route = 1;
            } else if (meta.bgp_info.prefix == 0x20010DB800040001) {
                meta.bgp_info.community = 0x65002; // Community: 65002:4
                meta.valid_route = 1;
            } else if (meta.bgp_info.prefix == 0x20010DB800050001) {
                meta.bgp_info.community = 0x65002; // Community: 65002:5
                meta.valid_route = 1;
            }
        }

        // Forward valid routes, drop invalid ones
        if (meta.valid_route == 1) {
            forward();
        } else {
            drop(); // Drop invalid or unmatched routes
        }
    }
}

control egress {
    apply {
        // Optional egress processing
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
