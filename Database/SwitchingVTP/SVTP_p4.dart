#include <core.p4>

// Header Definitions
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header vlan_t {
    bit<12> vlan_id;
    bit<3> priority;
    bit<1> cfi;
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

// Metadata Definitions
struct metadata_t {}

// Header Stack
struct headers {
    ethernet_t ethernet;
    vlan_t vlan;
    ipv4_t ipv4;
}

// Parser
parser my_parser(packet_in packet,
                 out headers hdr,
                 inout metadata_t meta,
                 inout standard_metadata_t standard_metadata) {
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x8100: parse_vlan; // VLAN-tagged packets
            0x0800: parse_ipv4; // IPv4 packets
            default: accept;
        }
    }

    state parse_vlan {
        packet.extract(hdr.vlan);
        transition parse_ipv4;
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
}

// Match-Action Table for VLAN Forwarding
table vlan_forwarding {
    key = {
        hdr.vlan.vlan_id: exact;
        hdr.ipv4.dstAddr: lpm; // Longest Prefix Match
    }
    actions = {
        vlan_forward;
        drop;
    }
    size = 1024;
    default_action = drop();
}

// Actions
action vlan_forward(bit<9> egress_port, bit<48> new_dst_mac) {
    standard_metadata.egress_spec = egress_port;
    hdr.ethernet.dstAddr = new_dst_mac;
}

action drop() {
    mark_to_drop();
}

// Control Logic
control my_control(inout headers hdr,
                   inout metadata_t meta,
                   inout standard_metadata_t standard_metadata) {
    apply {
        if (hdr.vlan.isValid()) {
            vlan_forwarding.apply();
        }
    }
}

// Deparser
control my_deparser(packet_out packet,
                    in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.vlan);
        packet.emit(hdr.ipv4);
    }
}

// Main Pipeline
V1Switch(
    my_parser(),
    my_control(),
    my_deparser()
) main;
