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

header bgp_t {
    bit<16> marker;
    bit<16> length;
    bit<8>  type;
    bit<32> as_number;
    bit<32> next_hop_ip;
}

// Metadata
struct metadata_t {
    bit<16> vrf_table_id;
    bit<32> vpn_nexthop_ipv6;
    bit<1>  vpn_override;
}

// Header Stack
struct headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
    mpls_t mpls;
    bgp_t bgp;
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
        transition select(hdr.ipv4.protocol) {
            6: parse_bgp; // TCP protocol (BGP)
            default: accept;
        }
    }
    state parse_mpls {
        packet.extract(hdr.mpls);
        transition accept;
    }
    state parse_bgp {
        packet.extract(hdr.bgp);
        transition accept;
    }
}

// Ingress Processing
control MyIngress(inout headers hdr, inout metadata_t meta, inout standard_metadata_t standard_metadata) {
    // Action to override VPN next-hop
    action override_vpn_nexthop(bit<32> new_next_hop) {
        hdr.bgp.next_hop_ip = new_next_hop;
        meta.vpn_override = 1;
    }

    // Action to validate next-hop
    action validate_nexthop(bit<32> expected_next_hop) {
        if (hdr.bgp.next_hop_ip != expected_next_hop) {
            mark_to_drop(); // Drop if next-hop is invalid
        }
    }

    // Table for VPN next-hop override
    table vpn_nexthop_override_table {
        key = {
            hdr.bgp.as_number: exact;
        }
        actions = {
            override_vpn_nexthop;
            NoAction;
        }
        size = 4;
    }

    // Table for validating next-hop
    table nexthop_validation_table {
        key = {
            hdr.bgp.next_hop_ip: exact;
        }
        actions = {
            validate_nexthop;
            NoAction;
        }
        size = 4;
    }

    apply {
        if (hdr.bgp.isValid()) {
            vpn_nexthop_override_table.apply();
            nexthop_validation_table.apply();
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
        packet.emit(hdr.bgp);
    }
}

// Main Control Pipeline
control main {
    MyParser() parser;
    MyIngress() ingress;
    MyEgress() egress;
    MyDeparser() deparser;
}
