// P4 Program for BGP Self Prefix Topology

#include <core.p4>
#include <v1model.p4>

// Define constants
const bit<48> BROADCAST_MAC = 0xFFFFFFFFFFFF;
const bit<32> DEFAULT_ROUTE = 0x00000000;     // 0.0.0.0
const bit<32> DEFAULT_MASK = 0x00000000;      // /0 mask

// Header definitions
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

// Metadata definitions
struct metadata_t {
    bit<9> egress_port;
}

// Parser
parser MyParser(packet_in pkt, out ethernet_t eth, out ipv4_t ipv4) {
    state start {
        pkt.extract(eth);
        transition select(eth.etherType) {
            0x0800: parse_ipv4;  // IPv4
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(ipv4);
        transition accept;
    }
}

// Match-Action Table for IPv4 Routing
table ipv4_lpm {
    key = {
        hdr.ipv4.dstAddr: lpm;  // Longest prefix match on destination IP
    }
    actions = {
        ipv4_forward;
        drop;
    }
    size = 1024;
    default_action = drop;
}

// Match-Action Table for MAC Forwarding
table mac_forward {
    key = {
        hdr.ethernet.dstAddr: exact;
    }
    actions = {
        mac_forward_action;
        drop;
    }
    size = 512;
    default_action = drop;
}

// Actions
action ipv4_forward(bit<48> dst_mac, bit<9> port) {
    hdr.ethernet.dstAddr = dst_mac;
    standard_metadata.egress_spec = port;
}

action mac_forward_action(bit<9> port) {
    standard_metadata.egress_spec = port;
}

action drop() {
    mark_to_drop();
}

// Control Logic
control ingress {
    apply {
        // Apply MAC forwarding table
        mac_forward.apply();

        // Apply IPv4 longest prefix match table
        ipv4_lpm.apply();
    }
}

control egress {
    apply {
        // Add any additional egress processing here
    }
}

// Main program
control MyIngress(packet_in pkt, packet_out pkt_out, inout ethernet_t eth, inout ipv4_t ipv4) {
    MyParser();
    ingress();
    egress();
}

// Instantiate the pipeline
V1Switch(MyIngress(), MyEgress()) main;
