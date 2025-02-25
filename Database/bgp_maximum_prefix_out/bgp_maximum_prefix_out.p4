// P4 Program for BGP Maximum-Prefix-Out
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
    bit<32> max_prefix_out;     // Maximum-prefix-out limit
    bit<32> advertised_prefixes; // Number of advertised prefixes
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;         // Flag to check if the BGP route is valid
    bit<1> max_prefix_out_reached; // Flag to check if the max-prefix-out limit is reached
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
        // Maximum prefix-out limit for R1
        bit<32> max_prefix_out_limit = 3;

        // Check if the advertised prefix is valid
        if (meta.bgp_info.advertised_prefix != 0) {
            meta.valid_route = 1;
        }

        // Check if the maximum prefix-out limit is reached
        if (meta.bgp_info.advertised_prefixes >= max_prefix_out_limit) {
            meta.max_prefix_out_reached = 1;
        } else {
            meta.max_prefix_out_reached = 0;
        }

        // Forward the route if the BGP route is valid and max-prefix-out limit is not reached
        if (meta.valid_route == 1 && meta.max_prefix_out_reached == 0) {
            forward();
        } else if (meta.max_prefix_out_reached == 1) {
            drop(); // Drop the packet if max-prefix-out limit is reached
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
