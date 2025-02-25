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
    ipv4_addr prefix;          // Advertised prefix
    bit<8> source_protocol;    // Source protocol (e.g., static, connected, etc.)
    bit<1> valid;              // Valid route flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;        // Indicates whether the route is valid
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
        // Default route validity
        meta.valid_route = 0;

        // Match routes based on source protocol and neighbor
        if (meta.bgp_info.source_protocol == 1) { // Static routes
            if (hdr.ipv4.dstAddr == 0xC0A80102) { // Neighbor R2 (192.168.1.2)
                meta.valid_route = 1;
            }
        } else if (meta.bgp_info.source_protocol == 2) { // Connected routes
            if (hdr.ipv4.dstAddr == 0xC0A80202) { // Neighbor R3 (192.168.2.2)
                meta.valid_route = 1;
            }
        }

        // Forward valid routes, drop invalid ones
        if (meta.valid_route == 1) {
            forward();
        } else {
            drop(); // Drop invalid or unmatched routes
        }
    }
}

control egress {
    apply {
        // Optional egress processing
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
