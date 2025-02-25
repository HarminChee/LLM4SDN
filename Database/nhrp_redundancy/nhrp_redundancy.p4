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
            // Traffic to NHRP clients and servers
            if (hdr.ipv4.dstAddr == 0xAC100104 ||  // 172.16.1.4
                hdr.ipv4.dstAddr == 0xAC100105 ||  // 172.16.1.5
                hdr.ipv4.dstAddr == 0xAC100101 ||  // 172.16.1.1
                hdr.ipv4.dstAddr == 0xAC100102 ||  // 172.16.1.2
                hdr.ipv4.dstAddr == 0xAC100103) {  // 172.16.1.3
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 1; // Forward traffic
            }
            // Traffic to host
            else if (hdr.ipv4.dstAddr == 0x0A040407) {  // 10.4.4.7
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 2; // Forward to host
            } else {
                drop(); // Drop all other traffic
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
