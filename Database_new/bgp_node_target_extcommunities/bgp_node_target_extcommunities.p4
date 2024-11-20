// P4 Program for BGP Node Target Extended Communities
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
    ipv4_addr node_target[4];  // Node Target Extended Communities (up to 4 router IDs)
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;         // Flag to check if the BGP route is valid
    bit<1> node_target_match;   // Flag to check if the Node Target matches the router ID
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
        // Define the local router ID for matching (e.g., R3's router ID is 192.168.1.3)
        ipv4_addr local_router_id = 192.168.1.3;

        // Check if the advertised prefix is valid
        if (meta.bgp_info.advertised_prefix != 0) {
            meta.valid_route = 1;
        }

        // Check if the Node Target matches the local router ID
        meta.node_target_match = 0;
        for (int i = 0; i < 4; i++) {
            if (meta.bgp_info.node_target[i] == local_router_id) {
                meta.node_target_match = 1;
                break;
            }
        }

        // Forward the route if the BGP route is valid and the Node Target matches
        if (meta.valid_route == 1 && meta.node_target_match == 1) {
            forward();
        } else {
            drop(); // Drop the packet if the Node Target does not match
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
