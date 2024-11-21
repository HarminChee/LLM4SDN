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
    bit<32> local_preference;  // Local preference
    bit<1> no_export;          // No-export community flag
    ipv4_addr nexthop;         // Next hop for the route
    bit<16> as_path[4];        // AS path
    bit<1> ebgp_oad;           // EBGP-OAD flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;        // Flag to check if the BGP route is valid
    bit<1> advertise_allowed;  // Flag to indicate if advertisement is allowed
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
        // Check if the route is valid
        if (meta.bgp_info.advertised_prefix != 0) {
            meta.valid_route = 1;
        }

        // Check if the route is allowed to be advertised
        if (meta.bgp_info.no_export == 1 && meta.bgp_info.ebgp_oad == 0) {
            meta.advertise_allowed = 0; // No-export prevents advertisement to non-OAD peers
        } else {
            meta.advertise_allowed = 1;
        }

        // Forward the route if valid and advertisement is allowed
        if (meta.valid_route == 1 && meta.advertise_allowed == 1) {
            forward();
        } else {
            drop(); // Drop the packet if the route is not valid or advertisement is not allowed
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
