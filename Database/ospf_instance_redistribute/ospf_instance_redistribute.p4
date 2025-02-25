#include <core.p4>
#include <v1model.p4>

// Define headers
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

struct metadata_t { }

// Parsers
parser MyParser(packet_in packet,
                out ethernet_t eth_hdr,
                out ipv4_t ip_hdr) {
    state start {
        packet.extract(eth_hdr);
        transition select(eth_hdr.etherType) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }
    state parse_ipv4 {
        packet.extract(ip_hdr);
        transition accept;
    }
}

// Match-Action Tables
control MyIngress {
    action forward(bit<9> port) {
        standard_metadata.egress_spec = port;
    }

    action drop() {
        mark_to_drop();
    }

    action set_route(bit<32> nhop) {
        modify_field(hdr.ipv4.dstAddr, nhop);
    }

    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            forward;
            drop;
            set_route;
        }
        size = 1024;
    }

    apply {
        if (hdr.ipv4.isValid()) {
            ipv4_lpm.apply();
        }
    }
}

// Deparser
control MyDeparser(packet_out packet,
                   in ethernet_t eth_hdr,
                   in ipv4_t ip_hdr) {
    apply {
        packet.emit(eth_hdr);
        packet.emit(ip_hdr);
    }
}

// Pipeline
control MyPipeline {
    MyParser() parser;
    MyIngress() ingress;
    MyDeparser() deparser;
}
