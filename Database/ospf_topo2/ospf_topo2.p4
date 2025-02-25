// Define headers
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
    bit<8>  nextHeader;
    bit<8>  hopLimit;
    bit<128> srcAddr;
    bit<128> dstAddr;
}

// Define metadata
struct metadata_t {}

// Define headers and parser output
struct headers_t {
    ethernet_t ethernet;
    ipv4_t ipv4;
    ipv6_t ipv6;
}

// Parser
parser MyParser(packet_in packet,
                out headers_t hdr,
                inout metadata_t meta,
                inout standard_metadata_t standard_metadata) {
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            0x86DD: parse_ipv6;
            default: accept;
        }
    }
    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
    state parse_ipv6 {
        packet.extract(hdr.ipv6);
        transition accept;
    }
}

// IPv4 routing table
table ipv4_lpm {
    key = {
        hdr.ipv4.dstAddr: lpm;
    }
    actions = {
        drop;
        ipv4_forward;
    }
    size = 256;
    default_action = drop();
}

// IPv6 routing table
table ipv6_lpm {
    key = {
        hdr.ipv6.dstAddr: lpm;
    }
    actions = {
        drop;
        ipv6_forward;
    }
    size = 256;
    default_action = drop();
}

// Actions
action drop() {
    mark_to_drop();
}

action ipv4_forward(bit<48> dstAddr, bit<9> port) {
    modify_field(hdr.ethernet.dstAddr, dstAddr);
    modify_field(standard_metadata.egress_spec, port);
}

action ipv6_forward(bit<48> dstAddr, bit<9> port) {
    modify_field(hdr.ethernet.dstAddr, dstAddr);
    modify_field(standard_metadata.egress_spec, port);
}

// Ingress control
control MyIngress(inout headers_t hdr,
                  inout metadata_t meta,
                  inout standard_metadata_t standard_metadata) {
    apply(ipv4_lpm);
    apply(ipv6_lpm);
}

// Deparser
control MyDeparser(packet_out packet, in headers_t hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.ipv6);
    }
}

// Switch control
control MySwitch(packet_in packet,
                 packet_out packet,
                 inout headers_t hdr,
                 inout metadata_t meta,
                 inout standard_metadata_t standard_metadata) {
    MyParser() parser;
    MyIngress() ingress;
    MyDeparser() deparser;

    apply {
        parser.apply(packet, hdr, meta, standard_metadata);
        ingress.apply(hdr, meta, standard_metadata);
        deparser.apply(packet, hdr);
    }
}

// Instantiate the pipeline
MySwitch() main;
