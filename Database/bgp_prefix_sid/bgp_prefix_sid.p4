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

header mpls_t {
    bit<20> label;
    bit<3> exp;
    bit<1> bottom_of_stack;
    bit<8> ttl;
}

header bgp_t {
    ipv4_addr advertised_prefix; // Advertised IPv4 prefix
    bit<1> valid;                // Valid route flag
    bit<32> remote_label;        // Remote MPLS label
    bit<16> label_index;         // Label Index
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;          // Flag to check if the route is valid
    bit<1> propagated;           // Flag to indicate if the route is propagated
}

parser MyParser(packet_in pkt, out headers_t hdr, inout metadata_t meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4; // IPv4
            0x8847: parse_mpls; // MPLS
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition accept;
    }

    state parse_mpls {
        pkt.extract(hdr.mpls);
        transition accept;
    }
}

control ingress {
    apply {
        // Validate route based on advertised prefix
        if (meta.bgp_info.advertised_prefix != 0) {
            meta.valid_route = 1;
        } else {
            meta.valid_route = 0;
        }

        // Process MPLS label and propagate the route
        if (meta.valid_route == 1) {
            meta.propagated = 1;
        } else {
            meta.propagated = 0;
        }

        // Forward valid routes
        if (meta.propagated == 1) {
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
        pkt.emit(hdr.mpls);
    }
}

control MyVerifyChecksum(inout headers_t hdr) {
    apply { }
}

control MyComputeChecksum(inout headers_t hdr) {
    apply { }
}

V1Switch(MyParser(), MyVerifyChecksum(), ingress(), egress(), MyComputeChecksum(), MyDeparser()) main;
