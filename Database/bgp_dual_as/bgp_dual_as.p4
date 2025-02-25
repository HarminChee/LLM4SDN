// P4 Program for BGP Dual-AS Configuration
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

header bgp_t {
    bit<32> local_as;        // Local Autonomous System (AS) number
    bit<32> remote_as;       // Remote Autonomous System (AS) number
    bit<32> next_hop_ipv4;   // Next hop for IPv4 route
    bit<1> bgpState;         // BGP session state (1 if Established)
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_session;    // Flag to check if the BGP session is valid
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
        // Check if BGP session is valid based on AS numbers and session state
        if (hdr.ipv4.isValid()) {
            if (meta.bgp_info.local_as == 65000 && meta.bgp_info.remote_as == 65002) {
                if (meta.bgp_info.bgpState == 1) {  // BGP session is Established
                    meta.valid_session = 1;
                    forward(meta.bgp_info.next_hop_ipv4);
                } else {
                    // Drop if BGP session is not established
                    drop();
                }
            } else if (meta.bgp_info.local_as == 65002 && meta.bgp_info.remote_as == 65000) {
                if (meta.bgp_info.bgpState == 1) {  // BGP session is Established
                    meta.valid_session = 1;
                    forward(meta.bgp_info.next_hop_ipv4);
                } else {
                    // Drop if BGP session is not established
                    drop();
                }
            } else {
                // Drop if AS numbers do not match
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
