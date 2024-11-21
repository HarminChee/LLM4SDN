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
    ipv4_addr next_hop;          // Next hop
    bit<1> table_direct;         // Indicates redistribution from a specific table
    bit<1> valid;                // Valid route flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;          // Flag to check if the route is valid
    bit<1> redistributed;        // Flag to indicate if the route is redistributed
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
        // Define the expected routes and table-direct flag
        ipv4_addr redistributed_prefix = 172.31.0.10;
        ipv4_addr next_hop = 172.31.1.10;

        // Check if the route is redistributed from table 2200
        if (meta.bgp_info.advertised_prefix == redistributed_prefix &&
            meta.bgp_info.table_direct == 1) {
            meta.redistributed = 1; // Mark the route as redistributed
            meta.valid_route = 1;   // Mark the route as valid
        } else {
            meta.redistributed = 0;
            meta.valid_route = 0;   // Mark the route as invalid
        }

        // Forward valid redistributed routes
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
