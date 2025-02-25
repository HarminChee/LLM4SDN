// P4 Program for BGP Graceful Shutdown (GSHUT) with iBGP Peering
#include <core.p4>

header ethernet_t {
    mac_addr dstAddr;
    mac_addr srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4> version;
    bit<4> ihl;
    bit<8> diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3> flags;
    bit<13> fragOffset;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdrChecksum;
    ipv4_addr srcAddr;
    ipv4_addr dstAddr;
}

header bgp_graceful_shutdown_t {
    bit<1> gshut_enabled;    // 1 if Graceful Shutdown is enabled
    bit<8> local_pref;       // Local Preference (set to 0 during GSHUT)
    bit<32> community;       // Community value (GSHUT)
}

header bgp_t {
    bit<16> as_number;       // Autonomous System number
    ipv4_addr next_hop;      // Next-hop IP address
    bit<32> metric;          // Metric for the route
    ipv4_addr advertised_prefix; // Advertised prefix
}

struct metadata_t {
    bgp_graceful_shutdown_t gshut_info;
    bgp_t bgp_info;
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
        // Check if Graceful Shutdown is enabled
        if (meta.gshut_info.gshut_enabled == 1) {
            // Set Local Preference to 0 if Graceful Shutdown is enabled
            meta.gshut_info.local_pref = 0;
            // Set the community to GSHUT
            meta.gshut_info.community = 0xFFFF0000; // GSHUT community value
        } else {
            // Default Local Preference if Graceful Shutdown is not enabled
            meta.gshut_info.local_pref = 100;
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
