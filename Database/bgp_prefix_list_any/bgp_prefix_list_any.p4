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
    ipv4_addr advertised_prefix; // Advertised IPv4 prefix
    bit<1> valid;                // Valid route flag
    bit<1> matched_prefix_list;  // Prefix-list match flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;          // Flag to check if the route is valid
    bit<1> prefix_permitted;     // Flag to indicate if the prefix is permitted
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
        // Define the prefix-list rules (configured on R2)
        ipv4_addr prefix_list_ipv4[4] = {
            10.10.10.10,
            10.10.10.20,
            10.10.10.30,
            10.10.10.40
        };
        int prefix_list_count = 4;

        // Check if the advertised prefix matches the prefix-list
        meta.prefix_permitted = 0;
        for (int i = 0; i < prefix_list_count; i++) {
            if (meta.bgp_info.advertised_prefix == prefix_list_ipv4[i]) {
                meta.prefix_permitted = 1; // Prefix matches the prefix-list
                break;
            }
        }

        // Apply the prefix-list rules
        if (meta.prefix_permitted == 1) {
            meta.bgp_info.valid = 1; // Permit the route
        } else {
            meta.bgp_info.valid = 0; // Deny the route
        }

        // Forward valid routes
        if (meta.bgp_info.valid == 1) {
            forward();
        } else {
            drop(); // Drop invalid routes
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
