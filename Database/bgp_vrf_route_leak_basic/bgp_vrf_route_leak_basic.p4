#include <core.p4>
#include <v1model.p4>

// Define VRF IDs
#define VRF_DONNA 1
#define VRF_EVA 2
#define VRF_DEFAULT 0
#define VRF_ZITA 3

// Header definitions
header ethernet_t {
    macAddr dstAddr;
    macAddr srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4> version;
    bit<4> ihl;
    bit<8> diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3> flags;
    bit<13> fragOffset;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

// Metadata for VRF
struct vrf_metadata_t {
    bit<16> vrf_id;
}

// Parser
parser MyParser(packet_in pkt,
                out ethernet_t eth_hdr,
                out ipv4_t ipv4_hdr,
                out vrf_metadata_t meta) {
    state start {
        pkt.extract(eth_hdr);
        transition select(eth_hdr.etherType) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(ipv4_hdr);
        transition accept;
    }
}

// Match-Action Tables
table vrf_table {
    key = {
        meta.vrf_id: exact;
        ipv4_hdr.dstAddr: lpm;
    }
    actions = {
        set_nexthop;
        drop;
    }
    size = 1024;
}

action set_nexthop(bit<32> nexthop_ip, bit<16> nexthop_vrf) {
    // Set nexthop and forward
    ipv4_hdr.dstAddr = nexthop_ip;
    meta.vrf_id = nexthop_vrf;
}

action drop() {
    // Drop the packet
    mark_to_drop();
}

// Control
control ingress {
    apply {
        vrf_table.apply();
    }
}

control egress {
    apply {
        // Forward to nexthop
    }
}

// Deparser
control MyDeparser(packet_out pkt,
                   in ethernet_t eth_hdr,
                   in ipv4_t ipv4_hdr) {
    apply {
        pkt.emit(eth_hdr);
        pkt.emit(ipv4_hdr);
    }
}

// Main Pipeline
V1Switch(MyParser(), ingress(), egress(), MyDeparser()) main;
