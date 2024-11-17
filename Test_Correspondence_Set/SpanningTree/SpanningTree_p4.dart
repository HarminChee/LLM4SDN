#include <core.p4>

// Header Definitions
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header stp_t {
    bit<8> protocol_id;
    bit<8> version_id;
    bit<16> message_type;
    bit<16> flags;
    bit<64> root_id;
    bit<16> root_path_cost;
    bit<64> bridge_id;
    bit<16> port_id;
    bit<16> message_age;
    bit<16> max_age;
    bit<16> hello_time;
    bit<16> forward_delay;
}

// Metadata Definitions
struct metadata_t {}

// Header Stack
struct headers {
    ethernet_t ethernet;
    stp_t stp;
}

// Parser
parser my_parser(packet_in packet,
                 out headers hdr,
                 inout metadata_t meta,
                 inout standard_metadata_t standard_metadata) {
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x010B: parse_stp; // STP packets
            default: accept;
        }
    }

    state parse_stp {
        packet.extract(hdr.stp);
        transition accept;
    }
}

// Match-Action Table for STP
table stp_filter {
    key = {
        hdr.stp.protocol_id: exact;
        hdr.stp.root_id: exact;
    }
    actions = {
        forward_stp;
        drop;
    }
    size = 128;
    default_action = drop();
}

// Actions
action forward_stp() {
    // Forward STP frames to the designated ports
    standard_metadata.egress_spec = 0xFFFFFFFF; // Broadcast
}

action drop() {
    mark_to_drop();
}

// Control Logic
control my_control(inout headers hdr,
                   inout metadata_t meta,
                   inout standard_metadata_t standard_metadata) {
    apply {
        if (hdr.stp.isValid()) {
            stp_filter.apply();
        }
    }
}

// Deparser
control my_deparser(packet_out packet,
                    in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.stp);
    }
}

// Main Pipeline
V1Switch(
    my_parser(),
    my_control(),
    my_deparser()
) main;
