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

// Packet Metadata
struct metadata { }

// Header Union for Simplification
header_union packet_headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
    ipv6_t ipv6;
}

// Parser Implementation
parser MyParser(packet_in packet, out packet_headers hdr) {
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            0x86DD: parse_ipv6;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }

    state parse_ipv6 {
        packet.extract(hdr.ipv6);
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

    table ipv6_routing {
        key = { hdr.ipv6.dstAddr: lpm; }
        actions = { ipv6_forward; drop; }
        size = 1024;
    }

    action ipv4_forward(bit<48> dst_mac, bit<9> egress_port) {
        hdr.ethernet.dstAddr = dst_mac;
        sm.egress_spec = egress_port;
    }

    action ipv6_forward(bit<48> dst_mac, bit<9> egress_port) {
        hdr.ethernet.dstAddr = dst_mac;
        sm.egress_spec = egress_port;
    }

    action drop() {
        mark_to_drop();
    }

    apply {
        if (hdr.ipv4.isValid()) {
            ipv4_routing.apply();
        } else if (hdr.ipv6.isValid()) {
            ipv6_routing.apply();
        }
    }
}

// Deparser
control MyDeparser(packet_out packet, in packet_headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        if (hdr.ipv4.isValid()) {
            packet.emit(hdr.ipv4);
        } else if (hdr.ipv6.isValid()) {
            packet.emit(hdr.ipv6);
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
