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
    bit<32> remote_as;         // Remote AS number
    bit<32> local_as;          // Local AS number
    bit<8> local_role;         // Local BGP role (e.g., customer, provider, peer)
    bit<8> remote_role;        // Remote BGP role
    bit<1> valid;              // Valid route flag
    bit<1> role_mismatch;      // Role mismatch flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;        // Flag to check if the route is valid
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
        // Role validation logic
        meta.bgp_info.role_mismatch = 0;
        meta.bgp_info.valid = 0;

        if ((meta.bgp_info.local_role == 1 && meta.bgp_info.remote_role == 2) || // Provider-Customer
            (meta.bgp_info.local_role == 2 && meta.bgp_info.remote_role == 1) || // Customer-Provider
            (meta.bgp_info.local_role == 3 && meta.bgp_info.remote_role == 3)) { // Peer-Peer
            meta.bgp_info.valid = 1; // Role match
        } else {
            meta.bgp_info.role_mismatch = 1; // Role mismatch
        }

        // Forward valid routes
        if (meta.bgp_info.valid == 1) {
            forward();
        } else {
            drop();
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
