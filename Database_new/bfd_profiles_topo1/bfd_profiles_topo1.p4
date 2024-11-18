/*
 * P4 Program for the BFD Profiles Topology
 * Routers: R1, R2, R3, R4, R5, R6
 * Links: Connecting routers through switches with specific protocols
 * Layer 2 (Ethernet) and Layer 3 (IP) forwarding logic
 */

#include <core.p4>
#include <v1model.p4>

// Define Ethernet and IPv4/IPv6 header types
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

header ipv6_t {
    bit<4>  version;
    bit<8>  trafficClass;
    bit<20> flowLabel;
    bit<16> payloadLen;
    bit<8>  nextHdr;
    bit<8>  hopLimit;
    bit<128> srcAddr;
    bit<128> dstAddr;
}

// Metadata passed between stages
struct metadata_t {}

// Standard control plane interface for parsing Ethernet, IPv4, and IPv6
parser MyParser(packet_in pkt, out ethernet_t eth, inout metadata_t meta) {
    pkt.extract(eth);
    if (eth.etherType == 0x0800) {  // IPv4 EtherType
        pkt.extract(ipv4);
    } else if (eth.etherType == 0x86DD) {  // IPv6 EtherType
        pkt.extract(ipv6);
    }
}

// Match-action table for L2 (Ethernet) forwarding
table l2_forward {
    key = {
        hdr.ethernet.dstAddr: exact;
    }
    actions = {
        forward;
        _drop;
    }
    size = 1024;
}

// Match-action table for L3 (IPv4) forwarding
table l3_ipv4_forward {
    key = {
        hdr.ipv4.dstAddr: lpm;
    }
    actions = {
        ipv4_forward;
        _drop;
    }
    size = 1024;
}

// Match-action table for L3 (IPv6) forwarding
table l3_ipv6_forward {
    key = {
        hdr.ipv6.dstAddr: lpm;
    }
    actions = {
        ipv6_forward;
        _drop;
    }
    size = 1024;
}

// Action for forwarding packets to a specific port (L2)
action forward(bit<9> port) {
    standard_metadata.egress_spec = port;
}

// Action for forwarding IPv4 packets (L3)
action ipv4_forward(bit<48> dst_mac, bit<9> port) {
    hdr.ethernet.dstAddr = dst_mac;
    standard_metadata.egress_spec = port;
}

// Action for forwarding IPv6 packets (L3)
action ipv6_forward(bit<48> dst_mac, bit<9> port) {
    hdr.ethernet.dstAddr = dst_mac;
    standard_metadata.egress_spec = port;
}

// Drop action
action _drop() {
    mark_to_drop();
}

// Ingress control logic
control ingress_control {
    apply {
        // Apply L2 forwarding first
        l2_forward.apply();

        // If the packet is IPv4, apply L3 IPv4 forwarding
        if (hdr.ethernet.etherType == 0x0800) {
            l3_ipv4_forward.apply();
        }
        // If the packet is IPv6, apply L3 IPv6 forwarding
        else if (hdr.ethernet.etherType == 0x86DD) {
            l3_ipv6_forward.apply();
        }
    }
}

// Egress control logic (no specific egress processing in this example)
control egress_control {
    apply {
        // No custom egress logic in this simple example
    }
}

// Deparser to reassemble the packet
control MyDeparser(packet_out pkt, in ethernet_t eth) {
    pkt.emit(eth);
    if (eth.etherType == 0x0800) {
        pkt.emit(ipv4);
    } else if (eth.etherType == 0x86DD) {
        pkt.emit(ipv6);
    }
}

// Main switch pipeline
V1Switch(MyParser(), ingress_control(), egress_control(), MyDeparser()) main;
