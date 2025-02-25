// P4 Program for BGP eBGP Common Subnet NEXT_HOP Unchanged
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
    ipv4_addr next_hop_ipv4;        // NEXT_HOP for the route
    ipv4_addr advertised_prefix;    // Advertised prefix
    bit<1> unchanged_nexthop;       // 1 if NEXT_HOP is unchanged
}

struct metadata_t {
    bgp_nexthop_t bgp_info;
    bit<1> valid_route;             // Flag to check if the route is valid
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
        // Check if the NEXT_HOP is unchanged when routers share a common subnet
        if (hdr.ipv4.isValid()) {
            if (meta.bgp_info.unchanged_nexthop == 1) {
                if (meta.bgp_info.advertised_prefix == 0xAC100101) {  // 172.16.1.1/32
                    if (meta.bgp_info.next_hop_ipv4 == 0xC0A80101) {  // 192.168.1.1
                        // Route is valid, NEXT_HOP is unchanged
                        meta.valid_route = 1;
                        forward();
                    } else {
                        // Drop if NEXT_HOP is changed
                        drop();
                    }
                } else {
                    // Drop if advertised prefix does not match
                    drop();
                }
            } else {
                // Drop if NEXT_HOP is marked as changed
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
