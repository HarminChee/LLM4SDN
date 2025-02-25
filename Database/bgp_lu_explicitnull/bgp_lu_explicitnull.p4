// P4 Program for BGP-LU with Explicit-Null Label (Label 0)
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
    bit<3> exp; // Experimental bits
    bit<1> s;   // Bottom of stack
    bit<8> ttl;
}

header bgp_t {
    bit<16> as_number;         // Autonomous System number
    ipv4_addr advertised_prefix; // Advertised IPv4 prefix
    bit<32> mpls_label;        // MPLS label for the advertised prefix
}

struct metadata_t {
    bgp_t bgp_info;
    mpls_t mpls_info;
    bit<1> valid_route;         // Flag to check if the BGP route is valid
    bit<1> explicit_null;       // Flag to check if the label is explicit-null
    bit<1> mpls_enabled;        // Flag to check if MPLS is enabled
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
        // Check if MPLS is enabled and the label is valid
        if (meta.mpls_info.label == 0) {
            meta.explicit_null = 1;
        } else {
            meta.explicit_null = 0;
        }

        // Check if the advertised BGP prefix is valid
        if (meta.bgp_info.advertised_prefix != 0) {
            meta.valid_route = 1;
        }

        // Forward the packet if the MPLS label is valid (explicit-null) or BGP route is valid
        if (meta.valid_route == 1 || meta.explicit_null == 1) {
            forward();
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
        pkt.emit(hdr.mpls); // Emit MPLS label if applicable
    }
}

control MyVerifyChecksum(inout headers_t hdr) {
    apply { }
}

control MyComputeChecksum(inout headers_t hdr) {
    apply { }
}

V1Switch(MyParser(), MyVerifyChecksum(), ingress(), egress(), MyComputeChecksum(), MyDeparser()) main;
