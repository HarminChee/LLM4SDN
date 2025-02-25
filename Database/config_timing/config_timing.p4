#include <core.p4>
#include <v1model.p4>

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

header ipv6_t {
    bit<4> version;
    bit<8> trafficClass;
    bit<20> flowLabel;
    bit<16> payloadLen;
    bit<8> nextHeader;
    bit<8> hopLimit;
    bit<128> srcAddr;
    bit<128> dstAddr;
}

// Metadata for routing
struct routing_metadata_t {
    bit<32> next_hop_ip;    // For IPv4
    bit<128> next_hop_ipv6; // For IPv6
    bit<8> egress_port;
}

// Parser
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

// Match-Action Tables
// Table for IPv4 static routing
table ipv4_static_routing {
    key = {
        ipv4_hdr.dstAddr: lpm;
    }
    actions = {
        set_ipv4_next_hop;
        drop;
    }
    size = 1024;
}

// Table for IPv6 static routing
table ipv6_static_routing {
    key = {
        ipv6_hdr.dstAddr: lpm;
    }
    actions = {
        set_ipv6_next_hop;
        drop;
    }
    size = 1024;
}

// Actions
action set_ipv4_next_hop(bit<32> next_hop_ip, bit<8> egress_port) {
    meta.next_hop_ip = next_hop_ip;
    meta.egress_port = egress_port;
}

action set_ipv6_next_hop(bit<128> next_hop_ipv6, bit<8> egress_port) {
    meta.next_hop_ipv6 = next_hop_ipv6;
    meta.egress_port = egress_port;
}

action drop() {
    mark_to_drop();
}

// Control Logic
control ingress {
    apply {
        if (hdrs.ipv4.isValid()) {
            ipv4_static_routing.apply();
        } else if (hdrs.ipv6.isValid()) {
            ipv6_static_routing.apply();
        }
    }
}

control egress {
    apply {
        // Forward packet to the next hop
    }
}

// Deparser
control MyDeparser(packet_out pkt,
                   in ethernet_t eth_hdr,
                   in ipv4_t ipv4_hdr,
                   in ipv6_t ipv6_hdr) {
    apply {
        pkt.emit(eth_hdr);
        if (hdrs.ipv4.isValid()) {
            pkt.emit(ipv4_hdr);
        } else if (hdrs.ipv6.isValid()) {
            pkt.emit(ipv6_hdr);
        }
    }
}

// Main Pipeline
V1Switch(MyParser(), ingress(), egress(), MyDeparser()) main;
