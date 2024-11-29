// Define header types
header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16> etherType;
}

header ipv6_t {
    bit<4> version;
    bit<8> trafficClass;
    bit<20> flowLabel;
    bit<16> payloadLen;
    bit<8> nextHeader;
    bit<8> hopLimit;
    ipv6Addr_t srcAddr;
    ipv6Addr_t dstAddr;
}

// Define metadata
struct metadata_t {
    bit<8> ecmp_group;
}

// Define parser
parser MyParser(
    packet_in pkt,
    out headers hdr,
    inout metadata_t meta,
    inout standard_metadata_t standard_meta
) {
    state start {
        transition select(pkt.lookahead<bit<16>>()) {
            0x86DD: parse_ipv6; // IPv6 EtherType
            default: accept;
        }
    }
    state parse_ipv6 {
        pkt.extract(hdr.ipv6);
        transition accept;
    }
}

// Define ingress logic
control MyIngress(
    inout headers hdr,
    inout metadata_t meta,
    inout standard_metadata_t standard_meta
) {
    action set_ecmp_group(bit<8> group)
