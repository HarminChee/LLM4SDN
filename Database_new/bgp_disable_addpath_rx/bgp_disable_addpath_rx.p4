// P4 Program for BGP AddPath with RX Disabled
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

header bgp_addpath_t {
    bit<1> addpath_tx;            // 1 if AddPath TX is enabled
    bit<1> addpath_rx;            // 1 if AddPath RX is enabled
    bit<32> next_hop_ipv4;        // Next hop for IPv4 route
    bit<32> prefix;               // Advertised prefix
    bit<32> path_count;           // Number of paths advertised
}

struct metadata_t {
    bgp_addpath_t bgp_addpath_info;
    bit<1> valid_route;           // Flag to check if the route is valid
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
        // Check if AddPath TX is enabled and RX is disabled
        if (hdr.ipv4.isValid()) {
            if (meta.bgp_addpath_info.addpath_tx == 1) {
                if (hdr.ipv4.dstAddr == meta.bgp_addpath_info.prefix) {
                    // Forward the route if AddPath TX is enabled
                    forward(meta.bgp_addpath_info.next_hop_ipv4);
                }
            } else if (meta.bgp_addpath_info.addpath_rx == 0) {
                // Only accept two paths if AddPath RX is disabled
                if (meta.bgp_addpath_info.path_count <= 2) {
                    meta.valid_route = 1;
                    forward();
                } else {
                    // Drop if more than two paths are received
                    drop();
                }
            } else {
                // Drop invalid routes
                drop();
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
