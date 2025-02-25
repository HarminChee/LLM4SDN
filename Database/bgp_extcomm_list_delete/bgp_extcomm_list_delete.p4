// P4 Program for BGP Extended Community List Deletion with Route-Map
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

header bgp_extended_community_t {
    bit<1> rt_enabled;      // 1 if Route Target (RT) is present
    bit<1> soo_enabled;     // 1 if Site of Origin (SoO) is present
    bit<1> nt_enabled;      // 1 if Neighbor Target (NT) is present
    bit<32> rt_value;       // RT community value
    bit<32> soo_value;      // SoO community value
    bit<32> nt_value;       // NT community value
}

struct metadata_t {
    bgp_extended_community_t ext_comm;
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
        // Check if the extended communities (RT, SoO, NT) are enabled and delete them based on the route-map
        if (meta.ext_comm.rt_enabled == 1) {
            // Delete the RT community
            meta.ext_comm.rt_enabled = 0;
        }
        if (meta.ext_comm.soo_enabled == 1) {
            // Delete the SoO community
            meta.ext_comm.soo_enabled = 0;
        }
        if (meta.ext_comm.nt_enabled == 1) {
            // Delete the NT community
            meta.ext_comm.nt_enabled = 0;
        }

        // Forward the packet if the route is valid
        if (meta.valid_route == 1) {
            forward();
        } else {
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
