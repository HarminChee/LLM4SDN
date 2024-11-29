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

header ipv6_t {
    bit<128> srcAddr;
    bit<128> dstAddr;
    bit<8> nextHdr;
    bit<8> hopLimit;
}

header bgp_t {
    bit<16> community1;
    bit<16> community2;
    bit<32> large_community1;
    bit<32> large_community2;
}

header ospf_t {
    bit<3> pathType;
    bit<32> areaID;
}

// Metadata declaration
struct metadata_t {
    bit<32> nexthop; // Next-hop IP
    bit<9> port;     // Egress port
}

// Define parser
parser MyParser(packet_in pkt,
                out ethernet_t eth_hdr,
                out ipv4_t ipv4_hdr,
                out ipv6_t ipv6_hdr,
                out bgp_t bgp_hdr,
                out ospf_t ospf_hdr) {
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
table ipv4_routing {
    key = {
        ipv4_t.dstAddr: lpm;
    }
    actions = {
        set_bgp_attributes;
        set_ospf_attributes;
        drop;
    }
    size = 1024;
}

table ipv6_routing {
    key = {
        ipv6_t.dstAddr: lpm;
    }
    actions = {
        set_ospf6_attributes;
        drop;
    }
    size = 1024;
}

// Define actions
action set_bgp_attributes(bit<16> community1, bit<16> community2,
                          bit<32> large_community1, bit<32> large_community2) {
    bgp_hdr.community1 = community1;
    bgp_hdr.community2 = community2;
    bgp_hdr.large_community1 = large_community1;
    bgp_hdr.large_community2 = large_community2;
}

action set_ospf_attributes(bit<3> pathType, bit<32> areaID) {
    ospf_hdr.pathType = pathType;
    ospf_hdr.areaID = areaID;
}

action set_ospf6_attributes(bit<3> pathType, bit<32> areaID) {
    ospf_hdr.pathType = pathType;
    ospf_hdr.areaID = areaID;
}

action drop() {
    mark_to_drop();
}

// Define control blocks
control ingress {
    apply(ipv4_routing);
    apply(ipv6_routing);
}

control egress {
    // No additional processing in egress
}

control MyDeparser(packet_out pkt,
                   in ethernet_t eth_hdr,
                   in ipv4_t ipv4_hdr,
                   in ipv6_t ipv6_hdr,
                   in bgp_t bgp_hdr,
                   in ospf_t ospf_hdr) {
    apply {
        pkt.emit(eth_hdr);
        pkt.emit(ipv4_hdr);
        pkt.emit(ipv6_hdr);
        pkt.emit(bgp_hdr);
        pkt.emit(ospf_hdr);
    }
}

V1Switch(MyParser(), ingress(), egress(), MyDeparser()) main;
