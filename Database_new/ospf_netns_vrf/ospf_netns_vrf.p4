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

// Parsers
parser MyParser(packet_in packet,
                out ethernet_t eth_hdr,
                out ipv4_t ip_hdr,
                out ipv6_t ipv6_hdr,
                out ospf_t ospf_hdr) {
    state start {
        packet.extract(eth_hdr);
        transition select(eth_hdr.etherType) {
            0x0800: parse_ipv4;
            0x86DD: parse_ipv6;
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
    state parse_ipv6 {
        packet.extract(ipv6_hdr);
        transition accept;
    }
    state parse_ospf {
        packet.extract(ospf_hdr);
        transition accept;
    }
}

// Control Logic
control MyIngress {
    action forward(bit<9> port) {
        standard_metadata.egress_spec = port;
    }

    action drop() {
        mark_to_drop();
    }

    action set_route_ipv4(bit<32> nhop) {
        modify_field(hdr.ipv4.dstAddr, nhop);
    }

    action set_route_ipv6(bit<128> nhop) {
        modify_field(hdr.ipv6.dstAddr, nhop);
    }

    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            forward;
            drop;
            set_route_ipv4;
        }
        size = 1024;
    }

    table ipv6_lpm {
        key = {
            hdr.ipv6.dstAddr: lpm;
        }
        actions = {
            forward;
            drop;
            set_route_ipv6;
        }
        size = 1024;
    }

    apply {
        if (hdr.ipv4.isValid()) {
            ipv4_lpm.apply();
        } else if (hdr.ipv6.isValid()) {
            ipv6_lpm.apply();
        }
    }
}

// Deparser
control MyDeparser(packet_out packet,
                   in ethernet_t eth_hdr,
                   in ipv4_t ip_hdr,
                   in ipv6_t ipv6_hdr,
                   in ospf_t ospf_hdr) {
    apply {
        packet.emit(eth_hdr);
        if (hdr.ipv4.isValid()) {
            packet.emit(ip_hdr);
        } else if (hdr.ipv6.isValid()) {
            packet.emit(ipv6_hdr);
        }
        if (ospf_hdr.isValid()) {
            packet.emit(ospf_hdr);
        }
    }
}

// Pipeline
control MyPipeline {
    MyParser() parser;
    MyIngress() ingress;
    MyDeparser() deparser;
}
