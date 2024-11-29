#include <core.p4>
#include <v1model.p4>

// Header Definitions
header ethernet_t {
    mac_addr dst_addr;
    mac_addr src_addr;
    bit<16> ether_type;
}

header ipv4_t {
    bit<32> src_addr;
    bit<32> dst_addr;
    bit<8> ttl;
    bit<8> protocol;
}

// Metadata for packet processing
struct standard_metadata_t {
    bit<9>  egress_spec;
    bit<9>  ingress_port;
    bit<1>  drop;
}

// Parser
parser MyParser(packet_in pkt, out ethernet_t eth, out ipv4_t ipv4) {
    state start {
        pkt.extract(eth);
        transition select(eth.ether_type) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(ipv4);
        transition accept;
    }
}

// Table for IPv4 Routing (using longest prefix match)
table ipv4_routing {
    key = {
        ipv4.dst_addr: lpm;
    }
    actions = {
        forward;
        drop;
    }
    size = 1024;
}

action forward(bit<9> port) {
    standard_metadata.egress_spec = port;
}

action drop() {
    standard_metadata.drop = 1;
}

// Control Blocks
control ingress {
    apply {
        if (ipv4.isValid()) {
            ipv4_routing.apply();
        }
    }
}

control egress {
    apply {
        // Placeholder for egress processing (could add more logic here)
    }
}

// Main pipeline definition
control MyPipeline {
    MyParser();
    ingress();
    egress();
}

package MySwitch(MyPipeline());
