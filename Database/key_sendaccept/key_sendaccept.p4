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

header keychain_t {
    bit<8> key_id;
    bit<8> active; // 1 = active, 0 = inactive
}

// Packet Metadata
struct metadata { }

// Header Union for Simplification
header_union packet_headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
    keychain_t keychain;
}

// Parser Implementation
parser MyParser(packet_in packet, out packet_headers hdr) {
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
}

// Match-Action Tables
control MyIngress(inout packet_headers hdr, inout metadata meta, inout standard_metadata_t sm) {
    table keychain_verification {
        key = { hdr.keychain.key_id: exact; }
        actions = { activate_key; deactivate_key; drop; }
        size = 1024;
    }

    action activate_key(bit<8> key_id) {
        hdr.keychain.key_id = key_id;
        hdr.keychain.active = 1;
    }

    action deactivate_key(bit<8> key_id) {
        hdr.keychain.key_id = key_id;
        hdr.keychain.active = 0;
    }

    action drop() {
        mark_to_drop();
    }

    apply {
        if (hdr.keychain.isValid()) {
            keychain_verification.apply();
        }
    }
}

// Deparser
control MyDeparser(packet_out packet, in packet_headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        if (hdr.ipv4.isValid()) {
            packet.emit(hdr.ipv4);
        }
        if (hdr.keychain.isValid()) {
            packet.emit(hdr.keychain);
        }
    }
}

// Pipeline Configuration
V1Switch(
    MyParser(),
    MyIngress(),
    MyEgress(),
    MyDeparser()
) main;
