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

header ipv6_t {
    bit<128> srcAddr;
    bit<128> dstAddr;
    bit<8> nextHdr;
    bit<8> hopLimit;
}

header vrf_metadata_t {
    bit<32> vrf_id;
}

// Metadata declaration
struct metadata_t {
    vrf_metadata_t vrf;
}

// Define parser
parser MyParser(packet_in pkt,
                out ethernet_t eth_hdr,
                out ipv4_t ipv4_hdr,
                out ipv6_t ipv6_hdr) {
    state start {
        pkt.extract(eth_hdr);
        transition select(eth_hdr.etherType) {
            0x0800: parse_ipv4; // IPv4
            0x86DD: parse_ipv6; // IPv6
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(ipv4_hdr);
        transition accept;
    }
    state parse_ipv6 {
        pkt.extract(ipv6_hdr);
        transition accept;
    }
}

// Define match-action tables
table ipv4_static_routes {
    key = {
        ipv4_t.dstAddr: lpm;
        metadata_t.vrf.vrf_id: exact;
    }
    actions = {
        ipv4_forward;
        blackhole;
        drop;
    }
    size = 1024;
}

table ipv6_static_routes {
    key = {
        ipv6_t.dstAddr: lpm;
        metadata_t.vrf.vrf_id: exact;
    }
    actions = {
        ipv6_forward;
        blackhole;
        drop;
    }
    size = 1024;
}

// Define actions
action ipv4_forward(bit<32> next_hop, bit<9> port) {
    ipv4_t.srcAddr = next_hop;
    standard_metadata.egress_spec = port;
}

action ipv6_forward(bit<128> next_hop, bit<9> port) {
    ipv6_t.srcAddr = next_hop;
    standard_metadata.egress_spec = port;
}

action blackhole() {
    mark_to_drop();
}

action drop() {
    mark_to_drop();
}

// Define control blocks
control ingress {
    apply(ipv4_static_routes);
    apply(ipv6_static_routes);
}

control egress {
    // No additional processing in egress
}

control MyDeparser(packet_out pkt,
                   in ethernet_t eth_hdr,
                   in ipv4_t ipv4_hdr,
                   in ipv6_t ipv6_hdr) {
    apply {
        pkt.emit(eth_hdr);
        pkt.emit(ipv4_hdr);
        pkt.emit(ipv6_hdr);
    }
}

V1Switch(MyParser(), ingress(), egress(), MyDeparser()) main;
