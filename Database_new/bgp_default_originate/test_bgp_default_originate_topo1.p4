// P4 Program for BGP Default-Originate with IBGP/EBGP and Route-Maps
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

header ipv6_t {
    bit<4>    version;
    bit<8>    trafficClass;
    bit<20>   flowLabel;
    bit<16>   payloadLen;
    bit<8>    nextHdr;
    bit<8>    hopLimit;
    ipv6_addr srcAddr;
    ipv6_addr dstAddr;
}

header bgp_default_t {
    bit<1> default_originate;     // 1 if default-originate is enabled
    bit<32> next_hop_ipv4;        // Next hop for IPv4 default route
    ipv6_addr next_hop_ipv6;      // Next hop for IPv6 default route
}

struct metadata_t {
    bgp_default_t bgp_default_info;
    bit<1> valid_route;           // Flag to check if the route is valid
    bit<1> route_map_applied;     // 1 if a route-map is applied
}

parser MyParser(packet_in pkt, out headers_t hdr, inout metadata_t meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            0x86dd: parse_ipv6;
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
}

control ingress {
    apply {
        if (hdr.ipv4.isValid()) {
            // Check if IPv4 default-originate is enabled and forward to the next hop
            if (meta.bgp_default_info.default_originate == 1) {
                if (hdr.ipv4.dstAddr == 0x00000000) {
                    if (meta.route_map_applied == 1) {
                        // Apply route-map logic (e.g., check prefix list)
                        meta.valid_route = 1;
                        forward(meta.bgp_default_info.next_hop_ipv4);
                    } else {
                        // No route-map, simply forward
                        meta.valid_route = 1;
                        forward(meta.bgp_default_info.next_hop_ipv4);
                    }
                }
            }
        } else if (hdr.ipv6.isValid()) {
            // Check if IPv6 default-originate is enabled and forward to the next hop
            if (meta.bgp_default_info.default_originate == 1) {
                if (hdr.ipv6.dstAddr == 0x00000000000000000000000000000000) {
                    if (meta.route_map_applied == 1) {
                        // Apply route-map logic (e.g., check prefix list)
                        meta.valid_route = 1;
                        forward(meta.bgp_default_info.next_hop_ipv6);
                    } else {
                        // No route-map, simply forward
                        meta.valid_route = 1;
                        forward(meta.bgp_default_info.next_hop_ipv6);
                    }
                }
            }
        } else {
            // Drop packets if no valid route
            drop();
        }
    }
}

control egress {
    apply {
        // Egress processing, if needed
    }
}

control MyDeparser(packet_out pkt, in headers_t hdr) {
    apply {
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
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
