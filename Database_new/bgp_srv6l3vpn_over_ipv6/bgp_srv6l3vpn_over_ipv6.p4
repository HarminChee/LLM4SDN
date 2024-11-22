// P4 Program for BGP SRv6 L3VPN over IPv6 Topology

#include <core.p4>
#include <v1model.p4>

// Header definitions
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header ipv6_t {
    bit<4>  version;
    bit<8>  trafficClass;
    bit<20> flowLabel;
    bit<16> payloadLength;
    bit<8>  nextHeader;
    bit<8>  hopLimit;
    bit<128> srcAddr;
    bit<128> dstAddr;
}

header srv6_t {
    bit<128> sid;
}

// Metadata definitions
struct metadata_t {
    bit<9> egress_port;
}

// Parser
parser MyParser(packet_in pkt, out ethernet_t eth, out ipv6_t ipv6, out srv6_t srv6) {
    state start {
        pkt.extract(eth);
        transition select(eth.etherType) {
            0x86DD: parse_ipv6;  // IPv6
            default: accept;
        }
    }
    state parse_ipv6 {
        pkt.extract(ipv6);
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

table ipv6_lpm {
    key = {
        hdr.ipv6.dstAddr: lpm;  // Longest prefix match for IPv6
    }
    actions = {
        ipv6_forward_action;
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

action ipv6_forward_action(bit<48> dst_mac, bit<9> port) {
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

        // Apply IPv6 forwarding rules
        ipv6_lpm.apply();

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
control MyDeparser(packet_out pkt, in ethernet_t eth, in ipv6_t ipv6, in srv6_t srv6) {
    apply {
        pkt.emit(eth);
        pkt.emit(ipv6);
        pkt.emit(srv6);
    }
}

// Main Pipeline
control MyIngress(packet_in pkt, packet_out pkt_out, inout ethernet_t eth, inout ipv6_t ipv6, inout srv6_t srv6) {
    MyParser();
    ingress();
    egress();
}

// Instantiate the pipeline
V1Switch(MyIngress(), MyDeparser()) main;
