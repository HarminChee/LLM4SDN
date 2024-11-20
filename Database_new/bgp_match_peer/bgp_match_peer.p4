// P4 Program for BGP Peer Matching with Route Advertisement
#include <core.p4>

header ethernet_t {
    mac_addr dstAddr;
    mac_addr srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4> version;
    bit<4> ihl;
    bit<8> diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3> flags;
    bit<13> fragOffset;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdrChecksum;
    ipv4_addr srcAddr;
    ipv4_addr dstAddr;
}

header bgp_t {
    bit<16> as_number;         // Autonomous System number
    ipv4_addr advertised_prefix; // Advertised IPv4 prefix
    bit<32> metric;            // BGP metric
    ipv4_addr next_hop;        // BGP next hop
    bit<16> peer_asn;          // Peer AS number
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;         // Flag to check if the BGP route is valid
    bit<1> peer_match;          // Flag to check if the peer matches
}

parser MyParser(packet_in pkt, out headers_t hdr, inout metadata_t meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4; // IPv4
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
        // Example: R1 only advertises 10.0.0.3/32 to R4 if the peer matches R3
        ipv4_addr r3_next_hop = 192.168.1.3;

        // Check if the advertised prefix is valid
        if (meta.bgp_info.advertised_prefix != 0) {
            meta.valid_route = 1;
        }

        // Check if the peer matches (R3 in this case)
        if (meta.bgp_info.next_hop == r3_next_hop) {
            meta.peer_match = 1;
        } else {
            meta.peer_match = 0;
        }

        // Forward the route if the BGP route is valid and the peer matches
        if (meta.valid_route == 1 && meta.peer_match == 1) {
            forward();
        } else {
            drop(); // Drop the packet if the peer doesn't match
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
