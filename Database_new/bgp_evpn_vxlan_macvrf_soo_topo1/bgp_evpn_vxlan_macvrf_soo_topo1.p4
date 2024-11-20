// P4 Program for BGP EVPN VXLAN with MAC-VRF SoO
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

header vxlan_t {
    bit<8> flags;
    bit<24> reserved;
    bit<24> vni;               // VXLAN Network Identifier (VNI)
    bit<8> reserved2;
}

header bgp_evpn_t {
    bit<1> type_2_enabled;      // 1 if EVPN Type-2 (MAC/IP) route is enabled
    bit<1> type_3_enabled;      // 1 if EVPN Type-3 (Inclusive Multicast) route is enabled
    bit<1> soo_enabled;         // 1 if Site of Origin (SoO) is enabled
    bit<32> prefix_ipv4;        // IPv4 prefix for Type-5 routes
    bit<48> mac;                // MAC address for Type-2 routes
    ipv4_addr ip_addr;          // IP address for Type-2 routes
    bit<64> soo;                // Site of Origin (SoO) community
}

struct metadata_t {
    bgp_evpn_t bgp_info;
    bit<1> valid_route;         // Flag to check if the route is valid
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
        // Check if EVPN Type-2, Type-3 routes are enabled and handle SoO
        if (meta.bgp_info.type_2_enabled == 1) {
            // Handle EVPN Type-2 (MAC/IP) route
            if (hdr.ethernet.srcAddr == meta.bgp_info.mac && hdr.ipv4.srcAddr == meta.bgp_info.ip_addr) {
                if (meta.bgp_info.soo_enabled == 1 && meta.bgp_info.soo == 6500000) {
                    // Uninstall the route if SoO matches the configured value
                    drop();
                } else {
                    // Forward the packet if MAC and IP match, and SoO does not block it
                    meta.valid_route = 1;
                    forward();
                }
            } else {
                // Drop if MAC/IP do not match
                drop();
            }
        } else if (meta.bgp_info.type_3_enabled == 1) {
            // Handle EVPN Type-3 (Inclusive Multicast) route
            if (meta.bgp_info.soo_enabled == 1 && meta.bgp_info.soo == 6500000) {
                // Uninstall the route if SoO matches the configured value
                drop();
            } else {
                // Forward the multicast packet
                meta.valid_route = 1;
                forward();
            }
        } else {
            // Drop if no route type is enabled
            drop();
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
