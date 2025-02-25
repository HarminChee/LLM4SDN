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

header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<3>  reserved;
    bit<9>  flags;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
    // TCP options (variable length, MSS included)
    bit<16> mss;
}

// Metadata
struct metadata_t {
    bit<16> tcp_mss_configured;
    bit<16> tcp_mss_synced;
}

// Header Stack
struct headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
    tcp_t tcp;
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
        transition select(hdr.ipv4.protocol) {
            6: parse_tcp; // TCP protocol
            default: accept;
        }
    }
    state parse_tcp {
        packet.extract(hdr.tcp);
        transition accept;
    }
}

// Ingress Processing
control MyIngress(inout headers hdr, inout metadata_t meta, inout standard_metadata_t standard_metadata) {
    // Action to configure TCP MSS
    action configure_tcp_mss(bit<16> mss) {
        meta.tcp_mss_configured = mss;
    }

    // Action to sync TCP MSS (adjust MSS based on headers, e.g., subtract IP/TCP overhead)
    action sync_tcp_mss() {
        // MSS synced = Configured MSS - (20 bytes IP header + 20 bytes TCP header)
        meta.tcp_mss_synced = meta.tcp_mss_configured - 40;
    }

    // Table for TCP MSS configuration
    table tcp_mss_config_table {
        key = {
            hdr.tcp.dstPort: exact; // Match on destination port (e.g., BGP 179)
        }
        actions = {
            configure_tcp_mss;
            NoAction;
        }
        size = 2;
    }

    apply {
        // Configure MSS for BGP sessions (port 179)
        if (hdr.tcp.dstPort == 179) {
            tcp_mss_config_table.apply();
            sync_tcp_mss();
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
        packet.emit(hdr.tcp);
    }
}

// Main Control Pipeline
control main {
    MyParser() parser;
    MyIngress() ingress;
    MyEgress() egress;
    MyDeparser() deparser;
}
