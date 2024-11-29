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

header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4> dataOffset;
    bit<4> reserved;
    bit<8> flags;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

// Metadata declaration
struct metadata_t {
    bit<32> rate_limit; // Rate limit in bits per second
}

// Define parser
parser MyParser(packet_in pkt,
                out ethernet_t eth_hdr,
                out ipv4_t ipv4_hdr,
                out tcp_t tcp_hdr) {
    state start {
        pkt.extract(eth_hdr);
        transition select(eth_hdr.etherType) {
            0x0800: parse_ipv4; // IPv4
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(ipv4_hdr);
        transition select(ipv4_hdr.protocol) {
            6: parse_tcp; // TCP
            default: accept;
        }
    }
    state parse_tcp {
        pkt.extract(tcp_hdr);
        transition accept;
    }
}

// Define match-action tables
table traffic_control {
    key = {
        ipv4_t.srcAddr: lpm;
        ipv4_t.dstAddr: lpm;
        tcp_t.srcPort: exact;
        tcp_t.dstPort: exact;
    }
    actions = {
        apply_rate_limit;
        drop;
    }
    size = 1024;
}

// Define actions
action apply_rate_limit(bit<32> rate_limit) {
    // Metadata rate_limit will be used by the scheduler for rate control
    metadata.rate_limit = rate_limit;
}

action drop() {
    mark_to_drop();
}

// Define control blocks
control ingress {
    apply(traffic_control);
}

control egress {
    // No additional processing in egress
}

control MyDeparser(packet_out pkt,
                   in ethernet_t eth_hdr,
                   in ipv4_t ipv4_hdr,
                   in tcp_t tcp_hdr) {
    apply {
        pkt.emit(eth_hdr);
        pkt.emit(ipv4_hdr);
        pkt.emit(tcp_hdr);
    }
}

V1Switch(MyParser(), ingress(), egress(), MyDeparser()) main;
