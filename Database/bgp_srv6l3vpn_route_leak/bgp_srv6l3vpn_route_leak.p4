// P4 Program for BGP SRv6 L3VPN Route Leak Topology

#include <core.p4>
#include <v1model.p4>

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

header srv6_t {
    bit<128> sid;
}

// Metadata definitions
struct metadata_t {
    bit<9> egress_port;
}

// Parser
parser MyParser(packet_in pkt, out ethernet_t eth, out ipv4_t ipv4, out srv6_t srv6) {
    state start {
        pkt.extract(eth);
        transition select(eth.etherType) {
            0x0800: parse_ipv4;  // IPv4
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(ipv4);
        transition srv6_start;
    }
    state srv6_start {
        pkt.extract(srv6);
        transition accept;
    }
}

// Match-Action Tables
table mac_forward {
    key = {
        hdr.ethernet.dstAddr: exact;  // Match destination MAC
    }
    actions = {
        mac_forward_action;
        drop;
    }
    size = 512;
    default_action = drop;
}

table ipv4_lpm {
    key = {
        hdr.ipv4.dstAddr: lpm;  // Longest prefix match for IPv4
    }
    actions = {
        ipv4_forward_action;
        drop;
    }
    size = 1024;
    default_action = drop;
}

table srv6_lookup {
    key = {
        hdr.srv6.sid: exact;  // Match SRv6 SID
    }
    actions = {
        srv6_forward_action;
        drop;
    }
    size = 256;
    default_action = drop;
}

// Actions
action mac_forward_action(bit<9> port) {
    standard_metadata.egress_spec = port;
}

action ipv4_forward_action(bit<48> dst_mac, bit<9> port) {
    hdr.ethernet.dstAddr = dst_mac;
    hdr.ethernet.srcAddr = smac;
    standard_metadata.egress_spec = port;
}

action srv6_forward_action(bit<128> next_sid, bit<9> port) {
    hdr.srv6.sid = next_sid;
    standard_metadata.egress_spec = port;
}

action drop() {
    mark_to_drop();
}

// Control Logic
control ingress {
    apply {
        // Apply MAC forwarding rules
        mac_forward.apply();

        // Apply IPv4 forwarding rules
        ipv4_lpm.apply();

        // Apply SRv6 forwarding rules
        srv6_lookup.apply();
    }
}

control egress {
    apply {
        // Add egress-specific processing, if needed
    }
}

// Deparser
control MyDeparser(packet_out pkt, in ethernet_t eth, in ipv4_t ipv4, in srv6_t srv6) {
    apply {
        pkt.emit(eth);
        pkt.emit(ipv4);
        pkt.emit(srv6);
    }
}

// Main Pipeline
control MyIngress(packet_in pkt, packet_out pkt_out, inout ethernet_t eth, inout ipv4_t ipv4, inout srv6_t srv6) {
    MyParser();
    ingress();
    egress();
}

// Instantiate the pipeline
V1Switch(MyIngress(), MyDeparser()) main;
