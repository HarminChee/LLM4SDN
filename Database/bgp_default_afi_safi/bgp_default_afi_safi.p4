// P4 Program for BGP AFI/SAFI Configuration
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

header bgp_afi_safi_t {
    bit<1> ipv4Unicast;      // 1 if IPv4 unicast is enabled
    bit<1> ipv6Unicast;      // 1 if IPv6 unicast is enabled
    bit<1> l2VpnEvpn;        // 1 if L2VPN EVPN is enabled
}

struct metadata_t {
    bgp_afi_safi_t afi_safi_info;
    bit<1> valid_route;      // Flag to check if the route is valid
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
        if (hdr.ipv4.isValid()) {
            // Check if the proper AFI/SAFI is enabled for IPv4 Unicast
            if (meta.afi_safi_info.ipv4Unicast == 1) {
                // Valid IPv4 Unicast route, forward the packet
                meta.valid_route = 1;
                forward();
            } else if (meta.afi_safi_info.ipv6Unicast == 1) {
                // Valid IPv6 Unicast route (assuming we have IPv6 headers), forward the packet
                meta.valid_route = 1;
                forward();
            } else if (meta.afi_safi_info.l2VpnEvpn == 1) {
                // Valid L2VPN EVPN route, forward the packet
                meta.valid_route = 1;
                forward();
            } else {
                // Drop if no valid AFI/SAFI is enabled
                meta.valid_route = 0;
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
