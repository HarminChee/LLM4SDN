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
    bit<32> as_path[8];          // AS Path (up to 8 ASNs for simplicity)
    bit<1> route_map_applied;    // Indicates if route-map was applied
    bit<1> valid;                // Valid route flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;          // Flag to check if the route is valid
    bit<1> private_as_removed;   // Flag to indicate private AS removal
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
        // Define private ASN range
        bit<32> private_as_min = 64512;
        bit<32> private_as_max = 65535;

        // Check if the route contains private ASNs
        meta.private_as_removed = 0;
        for (int i = 0; i < 8; i++) {
            if (meta.bgp_info.as_path[i] >= private_as_min &&
                meta.bgp_info.as_path[i] <= private_as_max) {
                // Remove private ASN
                meta.bgp_info.as_path[i] = 0;
                meta.private_as_removed = 1;
            }
        }

        // Mark the route as valid if all ASNs were processed correctly
        if (meta.private_as_removed == 1 || meta.bgp_info.as_path[0] != 0) {
            meta.valid_route = 1;
        } else {
            meta.valid_route = 0;
        }

        // Forward valid routes
        if (meta.valid_route == 1) {
            forward();
        } else {
            drop(); // Drop invalid routes
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
