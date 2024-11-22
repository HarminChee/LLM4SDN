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

// Metadata
struct metadata_t {
    bit<16> vrf_table_id;
    bit<32> next_hop_ip;
    bit<1>  vrf_imported;
    bit<1>  valid_next_hop;
}

// Header Stack
struct headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
}

// Parser
parser MyParser(packet_in packet, out headers hdr, inout metadata_t meta) {
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

// Ingress Processing
control MyIngress(inout headers hdr, inout metadata_t meta, inout standard_metadata_t standard_metadata) {
    // Action to import VRF route into the default VRF
    action import_vrf_route(bit<16> vrf_table, bit<32> next_hop) {
        meta.vrf_table_id = vrf_table;
        meta.next_hop_ip = next_hop;
        meta.vrf_imported = 1;
    }

    // Action to validate next-hop
    action validate_next_hop(bit<32> expected_next_hop) {
        if (meta.next_hop_ip == expected_next_hop) {
            meta.valid_next_hop = 1;
        } else {
            meta.valid_next_hop = 0;
            mark_to_drop(); // Drop if next-hop is invalid
        }
    }

    // Table for importing VRF routes
    table vrf_import_table {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            import_vrf_route;
            NoAction;
        }
        size = 256;
    }

    // Table for validating next-hop
    table next_hop_validation_table {
        key = {
            meta.next_hop_ip: exact;
        }
        actions = {
            validate_next_hop;
            NoAction;
        }
        size = 256;
    }

    apply {
        if (hdr.ipv4.isValid()) {
            vrf_import_table.apply();
            if (meta.vrf_imported == 1) {
                next_hop_validation_table.apply();
            }
        }
    }
}

// Egress Processing
control MyEgress(inout headers hdr, inout metadata_t meta, inout standard_metadata_t standard_metadata) {
    apply {
        // Egress processing if required
    }
}

// Deparser
control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
    }
}

// Main Control Pipeline
control main {
    MyParser() parser;
    MyIngress() ingress;
    MyEgress() egress;
    MyDeparser() deparser;
}
