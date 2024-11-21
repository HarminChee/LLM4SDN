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
    ipv4_addr advertised_prefix; // Advertised IPv4 prefix
    bit<16> local_as;            // Local AS number
    bit<16> remote_as;           // Remote AS number
    bit<1> valid;                // Valid route flag
    bit<1> peer_group;           // Peer group flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;          // Flag to check if the route is valid
    bit<16> remote_as;           // Remote AS number
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
        // Validate the route
        if (meta.bgp_info.advertised_prefix != 0) {
            meta.valid_route = 1;
        } else {
            meta.valid_route = 0;
        }

        // Assign remote AS numbers based on source IP
        if (hdr.ipv4.srcAddr == 192.168.1.2) {
            meta.remote_as = 65002; // R2
        } else if (hdr.ipv4.srcAddr == 192.168.1.3) {
            meta.remote_as = 65003; // R3
        }

        // Check if the BGP session is established
        if (meta.valid_route == 1 && meta.remote_as != 0) {
            meta.bgp_info.valid = 1; // Mark as valid
        } else {
            meta.bgp_info.valid = 0; // Mark as invalid
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
