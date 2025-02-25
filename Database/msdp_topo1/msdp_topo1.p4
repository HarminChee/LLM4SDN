#include <core.p4>

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

struct headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
}

parser MyParser(packet_in pkt, out headers hdr, inout standard_metadata_t standard_metadata) {
    state start {
        transition select(pkt.lookahead<ethernet_t>().etherType) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition accept;
    }
}

control ingress {
    apply {
        // IPv4 routing logic
        if (hdr.ipv4.isValid()) {
            // Match traffic to host h1
            if (hdr.ipv4.dstAddr == 0xC0A80464) {  // 192.168.4.100
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 4; // Forward to r4-eth1
            }
            // Match traffic to host h2
            else if (hdr.ipv4.dstAddr == 0xC0A80A64) {  // 192.168.10.100
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 2; // Forward to r1-eth1
            }
            // Match traffic to host h3
            else if (hdr.ipv4.dstAddr == 0xC0A80478) {  // 192.168.4.120
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 4; // Forward to r4-eth1
            }
            // Match traffic between routers
            else if (hdr.ipv4.dstAddr == 0xC0A80102) {  // 192.168.1.2
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 1; // Forward to r2-eth0
            } else if (hdr.ipv4.dstAddr == 0xC0A80202) {  // 192.168.2.2
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 3; // Forward to r3-eth0
            } else if (hdr.ipv4.dstAddr == 0xC0A80201) {  // 192.168.2.1
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 2; // Forward to r2-eth1
            } else {
                drop(); // Drop packet if no match
            }
        }
    }
}

control egress {
    apply {
        // Decrement TTL for all packets
        if (hdr.ipv4.isValid()) {
            hdr.ipv4.ttl -= 1;
        }
    }
}

deparser MyDeparser(packet_out pkt, in headers hdr) {
    apply {
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
    }
}

control MyIngress = ingress();
control MyEgress = egress();
parser MyParser = MyParser();
deparser MyDeparser = MyDeparser();
