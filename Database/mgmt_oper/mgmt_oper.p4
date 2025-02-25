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

header ipv6_t {
    bit<4>  version;
    bit<8>  trafficClass;
    bit<20> flowLabel;
    bit<16> payloadLen;
    bit<8>  nextHdr;
    bit<8>  hopLimit;
    bit<128> srcAddr;
    bit<128> dstAddr;
}

struct headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
    ipv6_t ipv6;
}

parser MyParser(packet_in pkt, out headers hdr, inout standard_metadata_t standard_metadata) {
    state start {
        transition select(pkt.lookahead<ethernet_t>().etherType) {
            0x0800: parse_ipv4;
            0x86DD: parse_ipv6;
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition accept;
    }
    state parse_ipv6 {
        pkt.extract(hdr.ipv6);
        transition accept;
    }
}

control ingress {
    apply {
        // IPv4 routing logic
        if (hdr.ipv4.isValid()) {
            if (hdr.ipv4.dstAddr == 0x6F000000) {  // 111.0.0.0/8
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 1; // Forward via r1-eth0
            } else if (hdr.ipv4.dstAddr == 0x37000000) {  // 55.0.0.0/8
                hdr.ipv4.ttl -= 1;
                standard_metadata.egress_spec = 1; // Forward via r1-eth0
            } else {
                drop(); // Drop packet if no match
            }
        }

        // IPv6 routing logic
        if (hdr.ipv6.isValid()) {
            if (hdr.ipv6.dstAddr[127:80] == 0x2111) {  // 2111::/48
                hdr.ipv6.hopLimit -= 1;
                standard_metadata.egress_spec = 2; // Forward via r1-eth1 (VRF red)
            } else if (hdr.ipv6.dstAddr[127:80] == 0x2055) {  // 2055::/48
                hdr.ipv6.hopLimit -= 1;
                standard_metadata.egress_spec = 1; // Forward via r1-eth0
            } else {
                drop(); // Drop packet if no match
            }
        }
    }
}

control egress {
    apply {
        // Decrement TTL or Hop Limit for all packets
        if (hdr.ipv4.isValid()) {
            hdr.ipv4.ttl -= 1;
        }
        if (hdr.ipv6.isValid()) {
            hdr.ipv6.hopLimit -= 1;
        }
    }
}

deparser MyDeparser(packet_out pkt, in headers hdr) {
    apply {
        pkt.emit(hdr.ethernet);
        if (hdr.ipv4.isValid()) {
            pkt.emit(hdr.ipv4);
        }
        if (hdr.ipv6.isValid()) {
            pkt.emit(hdr.ipv6);
        }
    }
}

control MyIngress = ingress();
control MyEgress = egress();
parser MyParser = MyParser();
deparser MyDeparser = MyDeparser();
