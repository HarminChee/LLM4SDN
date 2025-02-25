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
        // IPv4 access list filtering (ACL logic)
        if (hdr.ipv4.isValid()) {
            if (hdr.ipv4.srcAddr == 0x0A000001) {  // Match 10.0.0.1
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 1; // Permit forwarding
            } else if ((hdr.ipv4.srcAddr & 0xFF000000) == 0x0A000000) {  // Match 10.0.0.0/8
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 1; // Permit forwarding
            } else {
                drop(); // Deny all other traffic
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
