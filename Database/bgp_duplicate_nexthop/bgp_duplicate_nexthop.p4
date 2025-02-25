// P4 Program for BGP Duplicate Next-Hops
#include <core.p4>

header ethernet_t {
    mac_addr dstAddr;
    mac_addr srcAddr;
    bit<16>  etherType;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ipv4_addr srcAddr;
    ipv4_addr dstAddr;
}

header bgp_nexthop_t {
    bit<32> next_hop_ipv4;       // Next hop for IPv4 route
    bit<32> duplicate_next_hop;  // Duplicate next hop if applicable
    bit<16> labels[2];           // MPLS labels for the route
    bit<1>  active;              // 1 if the route is active
}

struct metadata_t {
    bgp_nexthop_t bgp_info;
    bit<1> valid_route;          // Flag to check if the route is valid
}

parser MyParser(packet_in pkt, out headers_t hdr, inout metadata_t meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
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
        // Check if the route is valid based on next-hop and duplicate next-hop
        if (hdr.ipv4.isValid()) {
            if (meta.bgp_info.active == 1) {  // Route is active
                if (meta.bgp_info.next_hop_ipv4 != meta.bgp_info.duplicate_next_hop) {
                    // Forward the route if next-hop and duplicate next-hop are different
                    meta.valid_route = 1;
                    forward(meta.bgp_info.next_hop_ipv4);
                } else {
                    // Drop if next-hop and duplicate next-hop are the same
                    drop();
                }
            } else {
                // Drop if the route is not active
                drop();
            }
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
