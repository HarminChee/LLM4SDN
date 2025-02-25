#include <core.p4>

header ethernet_t {
    mac_addr dstAddr;
    mac_addr srcAddr;
    bit<16> etherType;
}

header ipv6_t {
    bit<4> version;
    bit<8> trafficClass;
    bit<20> flowLabel;
    bit<16> payloadLen;
    bit<8> nextHdr;
    bit<8> hopLimit;
    ipv6_addr srcAddr;
    ipv6_addr dstAddr;
}

header bgp_t {
    ipv6_addr prefix;          // Advertised prefix
    ipv6_addr nexthop;         // Next-hop address
    bit<1> valid_gua;          // Valid Global Unicast Address flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;        // Indicates whether the route is valid
}

parser MyParser(packet_in pkt, out headers_t hdr, inout metadata_t meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x86DD: parse_ipv6; // IPv6
            default: accept;
        }
    }

    state parse_ipv6 {
        pkt.extract(hdr.ipv6);
        transition accept;
    }
}

control ingress {
    apply {
        // Default route validity
        meta.valid_route = 0;
        meta.bgp_info.valid_gua = 0;

        // Validate Global Unicast Address (GUA) for nexthop
        if (meta.bgp_info.nexthop >= 0x20010DB800000000 && // GUA range starts at 2000::/3
            meta.bgp_info.nexthop < 0x4000000000000000) {  // GUA range ends at 4000::/3
            meta.bgp_info.valid_gua = 1;
        }

        // Mark route as valid if GUA is valid
        if (meta.bgp_info.valid_gua == 1) {
            meta.valid_route = 1;
        }

        // Forward valid routes, drop invalid ones
        if (meta.valid_route == 1) {
            forward();
        } else {
            drop(); // Drop invalid or Link-Local nexthop routes
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
