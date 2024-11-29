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
    bit<16> checksum;
    bit<8> ttl;
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
            if (hdr.ipv4.dstAddr == 0xC0A80101) { // Route to Router 1
                forward(1); // Example port for r1
            } else if (hdr.ipv4.dstAddr == 0xC0A80102) { // Route to Router 2
                forward(2); // Example port for r2
            } else {
                drop();
            }
        } else {
            drop();
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
