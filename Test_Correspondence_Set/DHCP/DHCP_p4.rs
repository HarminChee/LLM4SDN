#include <core.p4>

// Define Header Fields
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
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
    bit<32> srcAddr;
    bit<32> dstAddr;
}

header dhcp_t {
    bit<32> xid;
    bit<16> flags;
    bit<32> ciaddr; // Client IP address
    bit<32> yiaddr; // Your (client) IP address
    bit<32> siaddr; // Next server IP address
    bit<32> giaddr; // Relay agent IP address
}

// Metadata Definitions
struct metadata_t {}

// Header Stack
struct headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
    dhcp_t dhcp;
}

// DHCP IP Allocation Table
table dhcp_ip_allocation {
    key = {
        hdr.dhcp.ciaddr: exact;
    }
    actions = {
        allocate_ip;
        drop;
    }
    size = 256;
    default_action = drop();
}

// Actions
action allocate_ip(bit<32> assigned_ip) {
    modify_field(hdr.dhcp.yiaddr, assigned_ip);
}

action drop() {
    mark_to_drop();
}

// Ingress Processing
control ingress {
    apply {
        if (hdr.dhcp.isValid()) {
            dhcp_ip_allocation.apply();
        } else {
            drop();
        }
    }
}

// Deparser
control deparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.dhcp);
    }
}

// Main Program
V1Switch(
    my_parser(),
    ingress(),
    egress(),
    deparser()
) main;
