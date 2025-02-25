// P4 Program for EVPN Multihoming with VXLAN
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

struct metadata_t {
    bit<1> esi_enabled;        // 1 if ESI is enabled for multihoming
    bit<48> esi;               // Ethernet Segment Identifier
    bit<1> df_role;            // 1 if the router is the Designated Forwarder (DF)
    bit<32> vni;               // VXLAN Network Identifier (VNI)
    bit<1> valid_route;        // 1 if the route is valid
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
        // Check if ESI is enabled for multihoming
        if (meta.esi_enabled == 1) {
            // Check if the router is the Designated Forwarder (DF)
            if (meta.df_role == 1) {
                // Forward the packet if DF
                forward();
            } else {
                // Drop the packet if not DF
                drop();
            }
        } else {
            // Normal forwarding if ESI is not enabled
            forward();
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
