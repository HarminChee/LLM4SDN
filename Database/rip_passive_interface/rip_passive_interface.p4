// Define header types
header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4> version;
    bit<4> ihl;
    bit<8> diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3> flags;
    bit<13> fragOffset;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdrChecksum;
    ipv4Addr_t srcAddr;
    ipv4Addr_t dstAddr;
}

// Define metadata
struct metadata_t {
    bit<8> rip_active; // Indicates if the interface is active in RIP
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
            0x0800: parse_ipv4;
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition accept;
    }
}

// Define ingress logic
control MyIngress(
    inout headers hdr,
    inout metadata_t meta,
    inout standard_metadata_t standard_meta
) {
    action set_rip_active(bit<8> status) {
        meta.rip_active = status;
    }

    apply {
        if (hdr.ipv4.isValid()) {
            // Define RIP passive/active interface logic
            if (hdr.ipv4.srcAddr == 192.168.1.2 && hdr.ipv4.dstAddr == 192.168.1.1) {
                set_rip_active(1); // eth0 on r2 is active
                standard_meta.egress_spec = 1; // Forward to r1
            } else if (hdr.ipv4.srcAddr == 192.168.2.1 && hdr.ipv4.dstAddr == 192.168.2.2) {
                set_rip_active(0); // eth1 on r2 is passive
                standard_meta.egress_spec = 2; // Forward to r3
            }
        }
    }
}

// Define egress logic
control MyEgress(
    inout headers hdr,
    inout metadata_t meta,
    inout standard_metadata_t standard_meta
) {
    apply {
        // Egress-specific logic (if any) can go here
    }
}

// Define deparser
control MyDeparser(
    packet_out pkt,
    in headers hdr
) {
    apply {
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
    }
}

// Define pipeline
pipeline MyPipeline(
    packet_in pkt,
    packet_out pkt_out
) {
    MyParser() parser;
    MyIngress() ingress;
    MyEgress() egress;
    MyDeparser() deparser;

    apply {
        parser.apply(pkt, hdr, meta, standard_meta);
        ingress.apply(hdr, meta, standard_meta);
        egress.apply(hdr, meta, standard_meta);
        deparser.apply(pkt_out, hdr);
    }
}

// Instantiate the pipeline
MyPipeline() main;
