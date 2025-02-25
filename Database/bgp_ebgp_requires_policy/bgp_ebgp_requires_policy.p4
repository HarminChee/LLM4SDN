// P4 Program for BGP eBGP Requires Policy (RFC8212) and iBGP
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

header bgp_policy_t {
    bit<1> ebgp_policy_required;  // 1 if eBGP policy required (RFC8212)
    bit<1> ibgp_session;          // 1 if iBGP session
    bit<32> advertised_prefix;    // Advertised prefix
    bit<1> valid_route;           // 1 if the route is valid
}

struct metadata_t {
    bgp_policy_t bgp_info;
    bit<1> valid_session;         // Flag to check if the BGP session is valid
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
        // Check if eBGP requires policy and if iBGP session is valid
        if (hdr.ipv4.isValid()) {
            if (meta.bgp_info.ibgp_session == 1) {
                // iBGP session, RFC8212 does not apply, all routes are valid
                meta.valid_session = 1;
                forward();
            } else {
                if (meta.bgp_info.ebgp_policy_required == 1) {
                    if (meta.bgp_info.valid_route == 1) {
                        // eBGP session with valid route and policy applied
                        meta.valid_session = 1;
                        forward();
                    } else {
                        // Drop if eBGP session without a valid route (no policy applied)
                        drop();
                    }
                } else {
                    // Drop if eBGP session without a required policy
                    drop();
                }
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
