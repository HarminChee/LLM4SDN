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
    ipv4_addr prefix;          // Advertised prefix
    bit<1> valid;              // Valid route flag
    bit<1> withdraw;           // Route withdrawal flag
    bit<32> delay_timer;       // Route delay timer in seconds
}

struct metadata_t {
    bgp_t bgp_info;
    bit<32> elapsed_time;      // Time since last route update
    bit<1> valid_update;       // Indicates whether the update is valid
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
        // Default route validity
        meta.valid_update = 0;

        // Check if route withdrawal is requested
        if (meta.bgp_info.withdraw == 1) {
            // If withdrawal, validate delay-timer
            if (meta.elapsed_time >= meta.bgp_info.delay_timer) {
                meta.valid_update = 1; // Withdraw route after delay
            } else {
                meta.valid_update = 0; // Delay withdrawal
            }
        } else {
            // For new routes or updates, mark as valid immediately
            meta.valid_update = 1;
        }

        // Forward valid updates, drop invalid ones
        if (meta.valid_update == 1) {
            forward();
        } else {
            drop(); // Drop updates that don't satisfy the delay timer
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
