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
        // L3 routing logic
        if (hdr.ipv4.isValid()) {
            if (hdr.ipv4.dstAddr == 0xAC100102) {  // 172.16.1.2
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 2; // Route to RT2
            } else if (hdr.ipv4.dstAddr == 0xAC100103) {  // 172.16.1.3
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 3; // Route to RT3
            } else if (hdr.ipv4.dstAddr == 0xAC100101) {  // 172.16.1.1
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 1; // Route to RT1
            } else {
                drop(); // Drop packet if no match
            }
        }

        // MPLS routing logic
        if (hdr.mpls.isValid()) {
            switch (hdr.mpls.label) {
                case 100: {
                    standard_metadata.egress_spec = 4; // Forward to RT1-RT2 link
                }
                case 200: {
                    standard_metadata.egress_spec = 5; // Forward to RT2-RT3 link
                }
                case 300: {
                    standard_metadata.egress_spec = 6; // Forward to RT3-RT1 link
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
