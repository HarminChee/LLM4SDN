// P4 Program for Dynamic BGP ORF Capability Exchange
#include <core.p4>

header ethernet_t {
    mac_addr dstAddr;
    mac_addr srcAddr;
    bit<16>  etherType;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ipv4_addr srcAddr;
    ipv4_addr dstAddr;
}

header bgp_orf_t {
    bit<1> orf_enabled;          // 1 if ORF capability is enabled
    bit<1> sendMode;             // 1 if ORF send mode is enabled
    bit<1> recvMode;             // 1 if ORF receive mode is enabled
    bit<32> prefix;              // Prefix being advertised or filtered
    bit<1> dynamic_capability;   // 1 if dynamic capabilities are enabled
}

struct metadata_t {
    bgp_orf_t bgp_orf_info;
    bit<1> valid_route;          // Flag to check if the route is valid
}

parser MyParser(packet_in pkt, out headers_t hdr, inout metadata_t meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition accept;
    }
}

control ingress {
    apply {
        // Check if the ORF capability is dynamically exchanged and if filtering is applied
        if (hdr.ipv4.isValid()) {
            if (meta.bgp_orf_info.dynamic_capability == 1) {
                if (meta.bgp_orf_info.orf_enabled == 1) {
                    if (meta.bgp_orf_info.sendMode == 1 && meta.bgp_orf_info.recvMode == 1) {
                        if (meta.bgp_orf_info.prefix == 0x0A0A0A14) {  // 10.10.10.20/32
                            meta.valid_route = 1;  // Route is valid, filter applied
                            forward();
                        } else {
                            // Drop if the prefix does not match the ORF filter
                            drop();
                        }
                    } else {
                        // Drop if ORF send/receive mode is not enabled
                        drop();
                    }
                } else {
                    // Drop if ORF capability is disabled
                    drop();
                }
            } else {
                // Drop if dynamic capabilities are not enabled
                drop();
            }
        }
    }
}

control egress {
    apply {
        // Egress processing if needed
    }
}

control MyDeparser(packet_out pkt, in headers_t hdr) {
    apply {
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
    }
}

control MyVerifyChecksum(inout headers_t hdr) {
    apply { }
}

control MyComputeChecksum(inout headers_t hdr) {
    apply { }
}

V1Switch(MyParser(), MyVerifyChecksum(), ingress(), egress(), MyComputeChecksum(), MyDeparser()) main;
