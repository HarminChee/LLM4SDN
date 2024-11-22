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
    bit<3> rpki_state;         // RPKI state (0: valid, 1: notfound, 2: invalid)
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

        // RPKI validation
        if (meta.bgp_info.rpki_state == 0) { // Valid RPKI state
            meta.valid_route = 1; // Mark route as valid
        } else if (meta.bgp_info.rpki_state == 1) { // Notfound RPKI state
            meta.valid_route = 0; // Drop route
        } else if (meta.bgp_info.rpki_state == 2) { // Invalid RPKI state
            meta.valid_route = 0; // Drop route
        }

        // Forward valid routes, drop invalid ones
        if (meta.valid_route == 1) {
            forward();
        } else {
            drop(); // Drop invalid or notfound routes
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
