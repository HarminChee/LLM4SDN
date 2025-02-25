// P4 Program for BGP Peering with IPv6 Link-Local Addresses
#include <core.p4>

header ethernet_t {
    mac_addr dstAddr;
    mac_addr srcAddr;
    bit<16> etherType;
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

header bgp_t {
    bit<16> as_number;       // Autonomous System number
    ipv6_addr neighbor_ipv6; // Neighbor IPv6 address (Link-Local)
    bit<32> afi_safi;        // Address Family Identifier (AFI) and Subsequent Address Family Identifier (SAFI)
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_session;     // Flag to check if the BGP session is valid
}

parser MyParser(packet_in pkt, out headers_t hdr, inout metadata_t meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x86DD: parse_ipv6;
            default: accept;
        }
    }

    state parse_ipv6 {
        pkt.extract(hdr.ipv6);
        transition accept;
    }
}

control ingress {
    apply {
        // Check if the source and destination IPv6 addresses are Link-Local
        if (hdr.ipv6.srcAddr >= 0xFE80000000000000 && hdr.ipv6.srcAddr <= 0xFEBF000000000000 &&
            hdr.ipv6.dstAddr >= 0xFE80000000000000 && hdr.ipv6.dstAddr <= 0xFEBF000000000000) {
            // Mark the session as valid if both addresses are Link-Local
            meta.valid_session = 1;
        } else {
            // Drop the packet if the addresses are not Link-Local
            drop();
        }

        // Forward the packet if the BGP session is valid
        if (meta.valid_session == 1) {
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
        pkt.emit(hdr.ipv6);
    }
}

control MyVerifyChecksum(inout headers_t hdr) {
    apply { }
}

control MyComputeChecksum(inout headers_t hdr) {
    apply { }
}

V1Switch(MyParser(), MyVerifyChecksum(), ingress(), egress(), MyComputeChecksum(), MyDeparser()) main;
