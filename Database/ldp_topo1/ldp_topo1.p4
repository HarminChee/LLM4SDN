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

header mpls_t {
    bit<20> label;
    bit<3>  exp;
    bit<1>  bos;
    bit<8>  ttl;
}

struct headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
    mpls_t mpls;
}

parser MyParser(packet_in pkt, out headers hdr, inout standard_metadata_t standard_metadata) {
    state start {
        transition select(pkt.lookahead<ethernet_t>().etherType) {
            0x0800: parse_ipv4;
            0x8847: parse_mpls;
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition accept;
    }
    state parse_mpls {
        pkt.extract(hdr.mpls);
        transition accept;
    }
}

control ingress {
    apply {
        // IPv4 routing logic
        if (hdr.ipv4.isValid()) {
            if (hdr.ipv4.dstAddr == 0x0A000102) {  // 10.0.1.2 (R2)
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 2; // Forward to R2
            } else if (hdr.ipv4.dstAddr == 0x0A000203) {  // 10.0.2.3 (R3)
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 3; // Forward to R3
            } else if (hdr.ipv4.dstAddr == 0x0A000204) {  // 10.0.2.4 (R4)
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 4; // Forward to R4
            } else {
                drop(); // Drop packet if no match
            }
        }

        // MPLS routing logic
        if (hdr.mpls.isValid()) {
            switch (hdr.mpls.label) {
                case 100: {
                    standard_metadata.egress_spec = 2; // Forward to R2
                }
                case 200: {
                    standard_metadata.egress_spec = 3; // Forward to R3
                }
                case 300: {
                    standard_metadata.egress_spec = 4; // Forward to R4
                }
                default: {
                    drop(); // Drop if no label match
                }
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
        if (hdr.mpls.isValid()) {
            pkt.emit(hdr.mpls);
        }
        pkt.emit(hdr.ipv4);
    }
}

control MyIngress = ingress();
control MyEgress = egress();
parser MyParser = MyParser();
deparser MyDeparser = MyDeparser();
