/*
 * P4 Program for the given topology
 * Routers: r1, r2, r3
 * Switches: sw1, sw2, sw3, sw4
 */

#include <core.p4>
#include <v1model.p4>

// Define header types
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

// Metadata definition
struct metadata_t {}

// Standard control plane interface
parser parse_ethernet(packet_in pkt, out ethernet_t eth, inout metadata_t metadata) {
    pkt.extract(eth);
    if (eth.etherType == 0x0800) {  // IPv4 EtherType
        parse_ipv4(pkt, eth, metadata);
    }
}

parser parse_ipv4(packet_in pkt, out ethernet_t eth, out ipv4_t ip, inout metadata_t metadata) {
    pkt.extract(ip);
}

control ingress_control {
    apply {
        // Basic L2 forwarding logic based on destination MAC address
        if (standard_metadata.ingress_port == 1) {
            // Forward packets from r1 to sw2
            if (hdr.ethernet.dstAddr == 0x02:00:00:00:02:00) {
                standard_metadata.egress_spec = 2;  // sw2 interface
            }
        } else if (standard_metadata.ingress_port == 2) {
            // Forward packets from r2 to sw3
            if (hdr.ethernet.dstAddr == 0x02:00:00:00:03:00) {
                standard_metadata.egress_spec = 3;  // sw3 interface
            }
        }
        // Add more forwarding rules as necessary based on the topology
    }
}

control egress_control {
    apply {
        // No specific egress processing in this simple example
    }
}

// Main control block
control MySwitch(
    inout ethernet_t hdr,
    inout metadata_t metadata,
    inout standard_metadata_t standard_metadata
) {
    apply {
        ingress_control.apply();
        egress_control.apply();
    }
}

control deparser(packet_out pkt, in ethernet_t eth, in metadata_t metadata) {
    pkt.emit(eth);
}

V1Switch(MySwitch(), MySwitchParser(), deparser()) main;
