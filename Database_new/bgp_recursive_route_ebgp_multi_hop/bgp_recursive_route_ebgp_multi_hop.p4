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
    ipv4_addr prefix;       // Advertised IPv4 prefix
    ipv4_addr next_hop;     // Next hop
    bit<32> as_path[4];     // AS Path
    bit<1> valid;           // Valid route flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;     // Flag to check if the route is valid
    bit<1> ecmp_candidate;  // Flag to indicate ECMP eligibility
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
        // Define expected routes and next-hops
        ipv4_addr expected_prefix = 100.1.1.1;
        ipv4_addr expected_next_hop_1 = 10.0.0.3;
        ipv4_addr expected_next_hop_2 = 20.0.0.2;

        // Validate the route
        if (meta.bgp_info.prefix == expected_prefix &&
            (meta.bgp_info.next_hop == expected_next_hop_1 ||
             meta.bgp_info.next_hop == expected_next_hop_2)) {
            meta.valid_route = 1; // Mark the route as valid
            meta.ecmp_candidate = 1; // Mark as ECMP candidate
        } else {
            meta.valid_route = 0; // Mark the route as invalid
        }

        // Forward valid routes
        if (meta.valid_route == 1) {
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
