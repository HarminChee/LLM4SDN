// P4 Program for BGP Labeled-Unicast with Default-Originate
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

header ipv6_t {
    bit<4> version;
    bit<8> traffic_class;
    bit<20> flow_label;
    bit<16> payload_length;
    bit<8> next_header;
    bit<8> hop_limit;
    ipv6_addr srcAddr;
    ipv6_addr dstAddr;
}

header mpls_t {
    bit<20> label;
    bit<3> exp; // Experimental bits
    bit<1> s;   // Bottom of stack
    bit<8> ttl;
}

header bgp_t {
    bit<16> as_number;         // Autonomous System number
    ipv4_addr advertised_prefix; // Advertised IPv4 prefix (default route)
    bit<32> vpn_label;         // VPN label for MPLS
    bit<32> metric;
    bit<32> community;         // BGP community
}

struct metadata_t {
    bgp_t bgp_info;
    mpls_t mpls_info;
    bit<1> valid_route;         // Flag to check if the BGP route is valid
    bit<1> valid_label;         // Flag to check if the MPLS label is valid
}

parser MyParser(packet_in pkt, out headers_t hdr, inout metadata_t meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4; // IPv4
            0x86DD: parse_ipv6; // IPv6
            0x8847: parse_mpls; // MPLS
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition accept;
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
        // Check if MPLS label is valid
        if (hdr.mpls.label != 0) {
            meta.valid_label = 1;
        }

        // Check if the advertised BGP prefix is valid (default route)
        if (meta.bgp_info.advertised_prefix == 0x00000000 || meta.bgp_info.advertised_prefix == 0x0000) {
            meta.valid_route = 1;
        }

        // Forward the packet if MPLS label and BGP route are valid
        if (meta.valid_label == 1 && meta.valid_route == 1) {
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
        pkt.emit(hdr.ipv4); // Emit IPv4 if applicable
        pkt.emit(hdr.ipv6); // Emit IPv6 if applicable
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
