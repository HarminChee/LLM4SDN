#include <core.p4>

// Header Definitions
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header ipv6_t {
    bit<4> version;
    bit<8> traffic_class;
    bit<20> flow_label;
    bit<16> payload_length;
    bit<8> next_header;
    bit<8> hop_limit;
    bit<128> srcAddr;
    bit<128> dstAddr;
}

// Metadata Definitions
struct metadata_t {}

// Header Stack
struct headers {
    ethernet_t ethernet;
    ipv6_t ipv6;
}

// Parser
parser my_parser(packet_in packet,
                 out headers hdr,
                 inout metadata_t meta,
                 inout standard_metadata_t standard_metadata) {
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x86DD: parse_ipv6; // IPv6 packets
            default: accept;
        }
    }

    state parse_ipv6 {
        packet.extract(hdr.ipv6);
        transition accept;
    }
}

// Match-Action Table for IPv6 Routing
table ipv6_routing {
    key = {
        hdr.ipv6.dstAddr: lpm; // Longest Prefix Match
    }
    actions = {
        ipv6_forward;
        drop;
    }
    size = 1024;
    default_action = drop();
}

// Actions
action ipv6_forward(bit<9> egress_port, bit<48> new_dst_mac) {
    standard_metadata.egress_spec = egress_port;
    hdr.ethernet.dstAddr = new_dst_mac;
    hdr.ethernet.srcAddr = hdr.ethernet.srcAddr;
}

action drop() {
    mark_to_drop();
}

// Control Logic
control my_control(inout headers hdr,
                   inout metadata_t meta,
                   inout standard_metadata_t standard_metadata) {
    apply {
        if (hdr.ipv6.isValid()) {
            ipv6_routing.apply();
        }
    }
}

// Deparser
control my_deparser(packet_out packet,
                    in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv6);
    }
}

// Main Pipeline
V1Switch(
    my_parser(),
    my_control(),
    my_deparser()
) main;
