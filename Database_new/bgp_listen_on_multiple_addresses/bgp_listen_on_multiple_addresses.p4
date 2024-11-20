// P4 Program for BGP Listening on Multiple Addresses
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
    bit<16> as_number;         // Autonomous System number
    ipv4_addr neighbor_addr;    // Neighbor's IP address
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_connection;    // Flag to check if the BGP connection is valid
}

parser MyParser(packet_in pkt, out headers_t hdr, inout metadata_t meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;  // IPv4
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
        // Define the list of valid listening addresses for each router
        ipv4_addr valid_addresses_r1[1] = {10.0.0.1};
        ipv4_addr valid_addresses_r2[2] = {10.0.0.2, 10.0.1.1};
        ipv4_addr valid_addresses_r3[2] = {10.0.1.2, 10.0.2.1};
        ipv4_addr valid_addresses_r4[1] = {10.0.2.2};

        // Example for router R2: Check if the packet is destined for a valid listening address
        if (hdr.ipv4.dstAddr == valid_addresses_r2[0] || hdr.ipv4.dstAddr == valid_addresses_r2[1]) {
            meta.valid_connection = 1;
        } else {
            meta.valid_connection = 0;
        }

        // Forward the packet if the connection is valid
        if (meta.valid_connection == 1) {
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
