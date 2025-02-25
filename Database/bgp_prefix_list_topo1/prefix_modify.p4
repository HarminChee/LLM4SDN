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
    bit<1> permit;               // Permit flag
    bit<1> deny;                 // Deny flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;          // Valid route flag
    bit<1> prefix_matched;       // Prefix-list match flag
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
        // Define prefix-list rules
        ipv4_addr deny_list[1] = {192.168.10.0}; // Deny prefix-list
        ipv4_addr permit_list[1] = {0.0.0.0};    // Permit any
        int deny_list_count = 1;
        int permit_list_count = 1;

        // Check if the advertised prefix matches the deny list
        meta.prefix_matched = 0;
        for (int i = 0; i < deny_list_count; i++) {
            if (meta.bgp_info.advertised_prefix == deny_list[i]) {
                meta.prefix_matched = 1; // Prefix matches the deny list
                meta.bgp_info.deny = 1;
                break;
            }
        }

        // If not denied, check if the prefix matches the permit list
        if (meta.prefix_matched == 0) {
            for (int i = 0; i < permit_list_count; i++) {
                if (meta.bgp_info.advertised_prefix == permit_list[i]) {
                    meta.prefix_matched = 1; // Prefix matches the permit list
                    meta.bgp_info.permit = 1;
                    break;
                }
            }
        }

        // Apply prefix-list rules
        meta.valid_route = (meta.bgp_info.permit == 1 && meta.bgp_info.deny == 0);

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
