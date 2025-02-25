// Define header types
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
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
    bit<32> srcAddr;
    bit<32> dstAddr;
}

// Define parser
parser MyParser(packet_in pkt,
                out ethernet_t ethernet,
                out ipv4_t ipv4) {
    state start {
        pkt.extract(ethernet);
        transition select(ethernet.etherType) {
            0x0800: parse_ipv4; // IPv4 EtherType
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(ipv4);
        transition accept;
    }
}

// Define control blocks
control MyIngress(inout headers_t hdr, inout metadata_t meta, inout standard_metadata_t standard_metadata) {
    action set_rp(bit<9> nexthop_group) {
        standard_metadata.egress_spec = nexthop_group;
    }

    apply {
        if (hdr.ipv4.isValid()) {
            if (hdr.ipv4.dstAddr >= 0xEF640000 && hdr.ipv4.dstAddr <= 0xEF64000F) {
                set_rp(11); // Forward to RP R11 for 239.100.0.0/28
            } else if (hdr.ipv4.dstAddr == 0xEF640011) {
                set_rp(12); // Forward to RP R12 for 239.100.0.17/32
            } else if (hdr.ipv4.dstAddr >= 0xEF640020 && hdr.ipv4.dstAddr <= 0xEF64003F) {
                set_rp(13); // Forward to RP R13 for 239.100.0.32/27
            } else if (hdr.ipv4.dstAddr >= 0xEF640080 && hdr.ipv4.dstAddr <= 0xEF6400FF) {
                set_rp(14); // Forward to RP R14 for 239.100.0.128/25
            } else if (hdr.ipv4.dstAddr >= 0xEF640060 && hdr.ipv4.dstAddr <= 0xEF64006F) {
                set_rp(15); // Forward to RP R15 for 239.100.0.64/28
            } else {
                standard_metadata.egress_spec = 0; // Drop packet
            }
        }
    }
}

// Define deparser
control MyDeparser(packet_out pkt,
                   in headers_t hdr) {
    apply {
        pkt.emit(hdr.ethernet);
        if (hdr.ipv4.isValid()) {
            pkt.emit(hdr.ipv4);
        }
    }
}

// Define pipeline
control MyPipeline {
    MyIngress() myIngress;
    MyDeparser() myDeparser;
}

// Instantiate the P4 switch
package MySwitch(MyParser(), MyPipeline(), MyDeparser());
MySwitch() main;
