// P4 Program for BGP Path Attribute Treat-as-Withdraw
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
    bit<16> as_number;         // Autonomous System number
    ipv4_addr advertised_prefix; // Advertised IPv4 prefix
    bit<1> atomic_aggregate;   // Atomic Aggregate attribute
    bit<1> withdrawn;          // Withdrawn flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;        // Flag to check if the BGP route is valid
    bit<1> treat_as_withdraw;  // Flag to indicate if the route should be withdrawn
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
        // Check if the advertised prefix is valid
        if (meta.bgp_info.advertised_prefix != 0) {
            meta.valid_route = 1;
        }

        // Apply the treat-as-withdraw behavior for paths with atomic-aggregate
        if (meta.bgp_info.atomic_aggregate == 1) {
            meta.treat_as_withdraw = 1;
            meta.bgp_info.withdrawn = 1; // Mark the route as withdrawn
        } else {
            meta.treat_as_withdraw = 0;
            meta.bgp_info.withdrawn = 0; // Route remains valid
        }

        // Forward the route if it is valid and not withdrawn
        if (meta.valid_route == 1 && meta.treat_as_withdraw == 0) {
            forward();
        } else {
            drop(); // Drop the packet if the route is withdrawn
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
