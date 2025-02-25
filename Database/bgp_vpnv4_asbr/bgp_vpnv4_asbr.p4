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

header mpls_t {
    bit<20> label;
    bit<3>  exp;
    bit<1>  s;
    bit<8>  ttl;
}

// Metadata
struct metadata_t {
    bit<16> vrf_table_id;
    bit<20> mpls_label;
    bit<32> next_hop_ip;
    bit<1>  vpnv4_route_valid;
}

// Header Stack
struct headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
    mpls_t mpls;
}

// Parser
parser MyParser(packet_in packet, out headers hdr, inout metadata_t meta) {
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            0x8847: parse_mpls; // MPLS label
            default: accept;
        }
    }
    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
    state parse_mpls {
        packet.extract(hdr.mpls);
        transition accept;
    }
}

// Ingress Processing
control MyIngress(inout headers hdr, inout metadata_t meta, inout standard_metadata_t standard_metadata) {
    // Action to forward based on MPLS label
    action forward_mpls(bit<20> label, bit<32> next_hop) {
        meta.mpls_label = label;
        meta.next_hop_ip = next_hop;
    }

    // Action to validate VPNv4 route
    action validate_vpnv4_route(bit<32> expected_next_hop) {
        if (meta.next_hop_ip == expected_next_hop) {
            meta.vpnv4_route_valid = 1;
        } else {
            meta.vpnv4_route_valid = 0;
            mark_to_drop(); // Drop if the next-hop is invalid
        }
    }

    // Table for MPLS forwarding
    table mpls_forwarding_table {
        key = {
            hdr.mpls.label: exact;
        }
        actions = {
            forward_mpls;
            NoAction;
        }
        size = 256;
    }

    // Table for validating VPNv4 routes
    table vpnv4_validation_table {
        key = {
            meta.next_hop_ip: exact;
        }
        actions = {
            validate_vpnv4_route;
            NoAction;
        }
        size = 256;
    }

    apply {
        if (hdr.mpls.isValid()) {
            mpls_forwarding_table.apply();
        }
        if (hdr.ipv4.isValid() && meta.vpnv4_route_valid == 0) {
            vpnv4_validation_table.apply();
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
        if (hdr.mpls.isValid()) {
            packet.emit(hdr.mpls);
        }
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
