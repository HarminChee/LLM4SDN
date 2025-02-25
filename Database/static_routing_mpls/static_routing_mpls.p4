#include <core.p4>
#include <v1model.p4>

// Define headers
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<32> srcAddr;
    bit<32> dstAddr;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdrChecksum;
}

header mpls_t {
    bit<20> label;
    bit<3> exp;
    bit<1> s;
    bit<8> ttl;
}

// Define parser
parser MyParser(packet_in pkt,
                out ethernet_t eth_hdr,
                out ipv4_t ipv4_hdr,
                out mpls_t mpls_hdr) {
    state start {
        pkt.extract(eth_hdr);
        transition select(eth_hdr.etherType) {
            0x0800: parse_ipv4; // IPv4
            0x8847: parse_mpls; // MPLS Unicast
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(ipv4_hdr);
        transition accept;
    }
    state parse_mpls {
        pkt.extract(mpls_hdr);
        transition accept;
    }
}

// Define match-action tables
table ipv4_lpm {
    key = {
        ipv4_t.dstAddr: lpm;
    }
    actions = {
        ipv4_forward;
        drop;
    }
    size = 1024;
}

table mpls_table {
    key = {
        mpls_t.label: exact;
    }
    actions = {
        mpls_forward;
        mpls_pop;
        drop;
    }
    size = 1024;
}

// Define actions
action ipv4_forward(bit<9> port) {
    standard_metadata.egress_spec = port;
}

action mpls_forward(bit<20> new_label, bit<9> port) {
    mpls_t.label = new_label;
    standard_metadata.egress_spec = port;
}

action mpls_pop() {
    remove(mpls_t);
}

action drop() {
    mark_to_drop();
}

// Define control blocks
control ingress {
    apply(ipv4_lpm);
    apply(mpls_table);
}

control egress {
    // No additional processing in egress
}

control MyDeparser(packet_out pkt,
                   in ethernet_t eth_hdr,
                   in ipv4_t ipv4_hdr,
                   in mpls_t mpls_hdr) {
    apply {
        pkt.emit(eth_hdr);
        pkt.emit(mpls_hdr);
        pkt.emit(ipv4_hdr);
    }
}

V1Switch(MyParser(), ingress(), egress(), MyDeparser()) main;
