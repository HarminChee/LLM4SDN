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

header mpls_t {
    bit<20> label;
    bit<3> exp;
    bit<1> bottom_of_stack;
    bit<8> ttl;
}

header bgp_t {
    ipv6_addr advertised_prefix; // Advertised IPv6 prefix
    bit<32> label;               // MPLS Label
    bit<1> valid;                // Valid route flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;          // Flag to check if the route is valid
}

parser MyParser(packet_in pkt, out headers_t hdr, inout metadata_t meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x86DD: parse_ipv6; // IPv6
            0x8847: parse_mpls; // MPLS
            default: accept;
        }
    }

    state parse_ipv6 {
        pkt.extract(hdr.ipv6);
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

        // Process MPLS label and validate the route
        if (meta.valid_route == 1) {
            meta.bgp_info.valid = 1; // Mark the route as valid
        } else {
            meta.bgp_info.valid = 0; // Mark the route as invalid
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
        pkt.emit(hdr.ipv6);
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
