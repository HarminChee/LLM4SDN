// P4 Program for BGP Outbound Route Filtering (ORF)
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
    bit<1> orf_capability;     // ORF capability flag
    bit<1> prefix_list_match;  // Flag to check if the prefix matches the prefix-list
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;         // Flag to check if the BGP route is valid
    bit<1> prefix_allowed;      // Flag to indicate if the prefix matches the prefix-list
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
        // Define the prefix-list for filtering (configured on R2)
        ipv4_addr prefix_list[2] = {10.10.10.1, 10.10.10.2};
        int prefix_list_count = 2;

        // Check if the advertised prefix is valid
        if (meta.bgp_info.advertised_prefix != 0) {
            meta.valid_route = 1;
        }

        // Check if the advertised prefix matches the prefix-list
        meta.prefix_allowed = 0;
        for (int i = 0; i < prefix_list_count; i++) {
            if (meta.bgp_info.advertised_prefix == prefix_list[i]) {
                meta.prefix_allowed = 1;
                break;
            }
        }

        // Forward the route if the BGP route is valid and matches the prefix-list
        if (meta.valid_route == 1 && meta.prefix_allowed == 1) {
            forward();
        } else {
            drop(); // Drop the packet if the route does not match the prefix-list
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
