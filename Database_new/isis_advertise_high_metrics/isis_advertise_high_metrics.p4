#include <core.p4>
#include <v1model.p4>

header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<32> srcAddr;
    bit<32> dstAddr;
    bit<8> protocol;
    bit<8> ttl;
    bit<16> checksum;
}

struct headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
}

parser MyParser(packet_in pkt,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            default: reject;
        }
    }
    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition accept;
    }
}

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {
    action forward(bit<9> port) {
        standard_metadata.egress_spec = port;
    }

    action drop() {
        standard_metadata.egress_spec = 0;
    }

    apply {
        if (hdr.ipv4.isValid()) {
            // Routing logic based on destination IP
            if (hdr.ipv4.dstAddr == 0xC0A80102) { // 192.168.1.2 (r2 via eth-r2)
                forward(1); // Port connected to s0 (r1 -> r2)
            } else if (hdr.ipv4.dstAddr == 0xC0A80103) { // 192.168.1.3 (r3 via eth-r3)
                forward(2); // Port connected to s1 (r1 -> r3)
            } else if (hdr.ipv4.dstAddr == 0xC0A80104) { // 192.168.1.4 (r4 via eth-r4 on r2)
                forward(3); // Port connected to s2 via r2
            } else {
                drop(); // Drop if no match
            }
        } else {
            drop(); // Drop non-IPv4 packets
        }
    }
}

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply { }
}

control MyVerifyChecksum(inout headers hdr,
                         inout metadata meta) {
    apply { }
}

control MyComputeChecksum(inout headers hdr,
                          inout metadata meta) {
    apply { }
}

deparser MyDeparser(packet_out pkt,
                    in headers hdr) {
    apply {
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
    }
}

V1Switch(MyParser(),
         MyVerifyChecksum(),
         MyIngress(),
         MyEgress(),
         MyComputeChecksum(),
         MyDeparser()) main;
