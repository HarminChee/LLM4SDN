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
    bit<8> protocol;
    bit<8> ttl;
    bit<16> checksum;
}

header mpls_t {
    bit<20> label;
    bit<3> exp;
    bit<1> s;
    bit<8> ttl;
}

// Metadata declaration
struct metadata_t {
    bit<32> nexthop;       // Next-hop IP
    bit<20> mpls_label;    // MPLS label
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
            0x8847: parse_mpls; // MPLS
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
table ipv4_routing {
    key = {
        ipv4_t.dstAddr: lpm;
    }
    actions = {
        set_nexthop;
        drop;
    }
    size = 1024;
}

table mpls_routing {
    key = {
        mpls_t.label: exact;
    }
    actions = {
        swap_label;
        pop_label;
        drop;
    }
    size = 1024;
}

// Define actions
action set_nexthop(bit<32> nexthop, bit<9> port) {
    metadata.nexthop = nexthop;
    standard_metadata.egress_spec = port;
}

action swap_label(bit<20> new_label, bit<9> port) {
    mpls_t.label = new_label;
    standard_metadata.egress_spec = port;
}

action pop_label() {
    remove(mpls_t);
}

action drop() {
    mark_to_drop();
}

// Define control blocks
control ingress {
    apply(ipv4_routing);
    apply(mpls_routing);
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
