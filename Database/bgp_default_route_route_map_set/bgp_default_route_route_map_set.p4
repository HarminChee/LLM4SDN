// P4 Program for BGP Default-Originate with Route-Map (Set Operations Only)
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

header bgp_default_t {
    bit<1> default_originate;     // 1 if default-originate is enabled
    bit<32> next_hop_ipv4;        // Next hop for IPv4 default route
    bit<32> metric;               // Metric for the default route
    bit<128> as_path;             // AS path for the default route (simplified for P4)
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
        // Check if the default route is being advertised or received
        if (hdr.ipv4.isValid()) {
            if (meta.bgp_default_info.default_originate == 1) {
                if (hdr.ipv4.dstAddr == 0x00000000) {  // Default route (0.0.0.0/0)
                    if (meta.route_map_applied == 1) {
                        // Apply route-map logic (set operations)
                        // Set the metric and AS path for the default route
                        meta.bgp_default_info.metric = 123;
                        meta.bgp_default_info.as_path = 0x65001650016500165001;  // Prepend AS path
                        meta.valid_route = 1;
                        forward(meta.bgp_default_info.next_hop_ipv4);
                    } else {
                        // No route-map, simply forward the default route
                        meta.valid_route = 1;
                        forward(meta.bgp_default_info.next_hop_ipv4);
                    }
                }
            } else {
                // Validate the received default route (0.0.0.0/0)
                if (hdr.ipv4.dstAddr == 0x00000000) {
                    meta.valid_route = 1;
                    forward();
                } else {
                    // Drop invalid routes
                    drop();
                }
            }
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
    }
}

control MyVerifyChecksum(inout headers_t hdr) {
    apply { }
}

control MyComputeChecksum(inout headers_t hdr) {
    apply { }
}

V1Switch(MyParser(), MyVerifyChecksum(), ingress(), egress(), MyComputeChecksum(), MyDeparser()) main;
