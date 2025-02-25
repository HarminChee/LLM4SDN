#include <core.p4>
#include <v1model.p4>

// Define headers
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header ipv6_t {
    bit<128> srcAddr;
    bit<128> dstAddr;
    bit<8> nextHdr;
    bit<8> hopLimit;
}

header srh_t {
    bit<8> nextHdr;
    bit<8> hdrExtLen;
    bit<8> segmentsLeft;
    bit<8> flags;
    bit<128> segmentList[4]; // Supports up to 4 segments
}

// Metadata declaration
struct metadata_t {
    bit<128> nexthop; // Next-hop IP
    bit<32> action;   // Action (e.g., encap)
}

// Define parser
parser MyParser(packet_in pkt,
                out ethernet_t eth_hdr,
                out ipv6_t ipv6_hdr,
                out srh_t srh_hdr) {
    state start {
        pkt.extract(eth_hdr);
        transition select(eth_hdr.etherType) {
            0x86DD: parse_ipv6; // IPv6
            default: accept;
        }
    }
    state parse_ipv6 {
        pkt.extract(ipv6_hdr);
        transition select(ipv6_hdr.nextHdr) {
            43: parse_srh; // Segment Routing Header (SRH)
            default: accept;
        }
    }
    state parse_srh {
        pkt.extract(srh_hdr);
        transition accept;
    }
}

// Define match-action tables
table ipv6_routing {
    key = {
        ipv6_t.dstAddr: lpm;
    }
    actions = {
        encap_seg6;
        drop;
    }
    size = 1024;
}

// Define actions
action encap_seg6(bit<128> nexthop, bit<128> seg_list[4]) {
    metadata.nexthop = nexthop;
    srh_t.segmentList[0] = seg_list[0];
    srh_t.segmentList[1] = seg_list[1];
    srh_t.segmentList[2] = seg_list[2];
    srh_t.segmentList[3] = seg_list[3];
    srh_t.segmentsLeft = 3; // Number of active segments
    ipv6_t.dstAddr = nexthop;
}

action drop() {
    mark_to_drop();
}

// Define control blocks
control ingress {
    apply(ipv6_routing);
}

control egress {
    // No additional processing in egress
}

control MyDeparser(packet_out pkt,
                   in ethernet_t eth_hdr,
                   in ipv6_t ipv6_hdr,
                   in srh_t srh_hdr) {
    apply {
        pkt.emit(eth_hdr);
        pkt.emit(ipv6_hdr);
        pkt.emit(srh_hdr);
    }
}

V1Switch(MyParser(), ingress(), egress(), MyDeparser()) main;
