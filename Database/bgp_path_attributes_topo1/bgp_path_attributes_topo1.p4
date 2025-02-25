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

header bgp_t {
    ipv4_addr advertised_prefix; // Advertised IPv4 prefix
    bit<16> as_path_length;      // AS Path Length
    bit<32> local_pref;          // Local Preference
    bit<16> med;                 // Multi-Exit Discriminator (MED)
    bit<32> weight;              // Weight
    bit<2> origin;               // Origin (IGP=0, EGP=1, INCOMPLETE=2)
    bit<16> admin_distance;      // Administrative Distance
}

struct metadata_t {
    bit<1> valid_route;          // Flag to check if the route is valid
    bit<1> best_path;            // Flag to indicate if this is the best path
    bgp_t bgp_info;              // BGP path attribute metadata
}

parser MyParser(packet_in pkt, out headers_t hdr, inout metadata_t meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4; // IPv4
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
        // Check if the route is valid
        if (meta.bgp_info.advertised_prefix != 0) {
            meta.valid_route = 1;
        }

        // Initialize best path flag
        meta.best_path = 0;

        // Best Path Selection Logic
        if (meta.valid_route == 1) {
            // NEXT_HOP Validation (Assume reachable)
            if (meta.bgp_info.as_path_length < 5) {  // Example condition
                meta.best_path = 1;
            }

            // LOCAL_PREF (Highest is better)
            if (meta.bgp_info.local_pref > 100) {
                meta.best_path = 1;
            }

            // WEIGHT (Highest is better)
            if (meta.bgp_info.weight > 500) {
                meta.best_path = 1;
            }

            // ORIGIN (IGP > EGP > INCOMPLETE)
            if (meta.bgp_info.origin == 0) {
                meta.best_path = 1;
            }

            // MED (Lowest is better)
            if (meta.bgp_info.med < 100) {
                meta.best_path = 1;
            }

            // ADMIN_DISTANCE (Lowest is better)
            if (meta.bgp_info.admin_distance < 100) {
                meta.best_path = 1;
            }
        }

        // Forward the best path
        if (meta.best_path == 1) {
            forward();
        } else {
            drop(); // Drop non-best paths
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
