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

header ospf_t {
    bit<8>  version;
    bit<8>  type;
    bit<16> pktLen;
    bit<32> routerID;
    bit<32> areaID;
    bit<16> checksum;
    bit<16> authType;
    bit<64> authData;
}

// Metadata Definition
struct metadata_t {
    bit<32> area_id; // OSPF area ID
}

// Parsers
parser MyParser(packet_in packet,
                out ethernet_t eth_hdr,
                out ipv4_t ip_hdr,
                out ospf_t ospf_hdr) {
    state start {
        packet.extract(eth_hdr);
        transition select(eth_hdr.etherType) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }
    state parse_ipv4 {
        packet.extract(ip_hdr);
        transition select(ip_hdr.protocol) {
            0x59: parse_ospf; // OSPF Protocol
            default: accept;
        }
    }
    state parse_ospf {
        packet.extract(ospf_hdr);
        transition accept;
    }
}

// Match-Action Pipeline
control MyIngress {
    // Actions
    action forward(bit<9> port) {
        standard_metadata.egress_spec = port;
    }

    action drop() {
        mark_to_drop();
    }

    action set_area(bit<32> area) {
        meta.area_id = area;
    }

    action set_nexthop(bit<32> nhop) {
        hdr.ipv4.dstAddr = nhop;
    }

    // Tables
    table ospf_area_table {
        key = {
            meta.area_id: exact;
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            forward;
            drop;
            set_nexthop;
        }
        size = 1024;
    }

    apply {
        if (hdr.ipv4.isValid()) {
            ospf_area_table.apply();
        }
    }
}

// Deparser
control MyDeparser(packet_out packet,
                   in ethernet_t eth_hdr,
                   in ipv4_t ip_hdr,
                   in ospf_t ospf_hdr) {
    apply {
        packet.emit(eth_hdr);
        packet.emit(ip_hdr);
        packet.emit(ospf_hdr);
    }
}

// Pipeline
control MyPipeline {
    MyParser() parser;
    MyIngress() ingress;
    MyDeparser() deparser;
}
