// P4 Program for BGP Dont-Capability-Negotiate and FQDN Capability
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

header bgp_capabilities_t {
    bit<1> dont_capability_negotiate;  // 1 if dont-capability-negotiate is enabled
    bit<1> fqdn_enabled;               // 1 if FQDN capability is enabled
    bit<32> next_hop_ipv4;             // Next hop for IPv4 route
    bit<16> pfxRcd;                    // Number of received prefixes
    bit<16> pfxSnt;                    // Number of sent prefixes
    bit<128> fqdn;                     // FQDN of the peer (if FQDN capability is enabled)
}

struct metadata_t {
    bgp_capabilities_t bgp_cap_info;
    bit<1> valid_route;                // Flag to check if the route is valid
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
        // Check if BGP session can be established based on capabilities
        if (hdr.ipv4.isValid()) {
            if (meta.bgp_cap_info.dont_capability_negotiate == 1) {
                // Dont-Capability-Negotiate is enabled, skip capability negotiation
                meta.valid_route = 1;
                forward(meta.bgp_cap_info.next_hop_ipv4);
            } else {
                // Check if capabilities are negotiated, including FQDN
                if (meta.bgp_cap_info.fqdn_enabled == 1) {
                    // FQDN capability is enabled, peer's hostname is included
                    meta.valid_route = 1;
                    forward(meta.bgp_cap_info.next_hop_ipv4);
                } else {
                    // Capabilities not negotiated, drop the session
                    drop();
                }
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
