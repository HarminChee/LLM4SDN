// P4 Program for the test_cspf_topo1.py topology

#include <core.p4>

#define MAX_PORTS 8

// Headers
header ethernet_t {
    bit<48> dst_addr;
    bit<48> src_addr;
    bit<16> eth_type;
}

header ipv4_t {
    bit<4> version;
    bit<4> ihl;
    bit<8> diffserv;
    bit<16> total_len;
    bit<16> identification;
    bit<3> flags;
    bit<13> frag_offset;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdr_checksum;
    bit<32> src_addr;
    bit<32> dst_addr;
}

header ipv6_t {
    bit<4> version;
    bit<8> traffic_class;
    bit<20> flow_label;
    bit<16> payload_len;
    bit<8> next_header;
    bit<8> hop_limit;
    bit<128> src_addr;
    bit<128> dst_addr;
}

// Parser
parser ParserImpl(packet_in packet,
                  out ethernet_t eth_hdr,
                  out ipv4_t ipv4_hdr,
                  out ipv6_t ipv6_hdr,
                  out bool is_ipv4,
                  out bool is_ipv6) {
    state start {
        packet.extract(eth_hdr);
        transition select(eth_hdr.eth_type) {
            0x0800: parse_ipv4;
            0x86DD: parse_ipv6;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(ipv4_hdr);
        is_ipv4 = true;
        transition accept;
    }

    state parse_ipv6 {
        packet.extract(ipv6_hdr);
        is_ipv6 = true;
        transition accept;
    }
}

// Match-Action Tables
table ipv4_forward {
    key = {
        hdr.ipv4.dst_addr: exact;
    }
    actions = {
        forward;
        drop;
    }
    size = 1024;
}

table ipv6_forward {
    key = {
        hdr.ipv6.dst_addr: exact;
    }
    actions = {
        forward;
        drop;
    }
    size = 1024;
}

// Actions
action forward(bit<9> port) {
    standard_metadata.egress_spec = port;
}

action drop() {
    mark_to_drop();
}

// Control Block
control IngressImpl(inout headers hdr,
                    inout metadata meta,
                    inout standard_metadata_t standard_metadata) {
    apply {
        if (hdr.is_ipv4) {
            ipv4_forward.apply();
        } else if (hdr.is_ipv6) {
            ipv6_forward.apply();
        }
    }
}

// Deparser
control DeparserImpl(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.eth_hdr);
        if (hdr.is_ipv4) {
            packet.emit(hdr.ipv4_hdr);
        } else if (hdr.is_ipv6) {
            packet.emit(hdr.ipv6_hdr);
        }
    }
}

// Main Pipeline
control MyPipeline(inout headers hdr,
                   inout metadata meta,
                   inout standard_metadata_t standard_metadata) {
    IngressImpl();
    DeparserImpl();
}

// Instantiate Main Pipeline
package MySwitch(ParserImpl(), MyPipeline(), DeparserImpl());
