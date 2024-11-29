#include <core.p4>
#include <v1model.p4>

// Header Definitions
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

header mpls_t {
    bit<20> label;
    bit<3>  exp;
    bit<1>  s;
    bit<8>  ttl;
}

// Packet Metadata
struct metadata { }

// Header Union for MPLS
header_union packet_headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
    mpls_t mpls;
}

// Parser Implementation
parser MyParser(packet_in packet, out packet_headers hdr) {
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            0x8847: parse_mpls; // MPLS Unicast
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }

    state parse_mpls {
        packet.extract(hdr.mpls);
        transition accept;
    }
}

// Match-Action Tables
control MyIngress(inout packet_headers hdr, inout metadata meta, inout standard_metadata_t sm) {
    table ipv4_routing {
        key = { hdr.ipv4.dstAddr: lpm; }
        actions = { ipv4_forward; drop; }
        size = 1024;
    }

    table mpls_routing {
        key = { hdr.mpls.label: exact; }
        actions = { mpls_forward; mpls_pop; drop; }
        size = 1024;
    }

    action ipv4_forward(bit<48> dst_mac, bit<9> egress_port) {
        hdr.ethernet.dstAddr = dst_mac;
        sm.egress_spec = egress_port;
    }

    action mpls_forward(bit<20> label, bit<9> egress_port) {
        hdr.mpls.label = label;
        sm.egress_spec = egress_port;
    }

    action mpls_pop() {
        hdr.mpls.setInvalid();
    }

    action drop() {
        mark_to_drop();
    }

    apply {
        if (hdr.ipv4.isValid()) {
            ipv4_routing.apply();
        } else if (hdr.mpls.isValid()) {
            mpls_routing.apply();
        }
    }
}

// Deparser
control MyDeparser(packet_out packet, in packet_headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        if (hdr.ipv4.isValid()) {
            packet.emit(hdr.ipv4);
        }
        if (hdr.mpls.isValid()) {
            packet.emit(hdr.mpls);
        }
    }
}

// Pipeline Configuration
V1Switch(
    MyParser(),
    MyIngress(),
    MyEgress(),
    MyDeparser()
) main;
