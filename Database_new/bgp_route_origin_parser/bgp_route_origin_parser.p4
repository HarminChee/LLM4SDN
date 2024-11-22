#include <core.p4>

header ethernet_t {
    mac_addr dstAddr;
    mac_addr srcAddr;
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
    ipv4_addr srcAddr;
    ipv4_addr dstAddr;
}

header bgp_t {
    bit<32> extended_community_asn; // 4-byte ASN value
    bit<16> extended_community_value; // Extended community value
    bit<1> valid;                    // Valid ASN flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_rt_community;       // Indicates whether the RT is valid
    bit<1> valid_soo_community;      // Indicates whether the SoO is valid
}

parser MyParser(packet_in pkt, out headers_t hdr, inout metadata_t meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800: parse_ipv4; // IPv4
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
        // Default validity
        meta.valid_rt_community = 0;
        meta.valid_soo_community = 0;

        // Validate Route Target (RT)
        if (meta.bgp_info.extended_community_asn <= 0xFFFFFFFF) { // Max valid ASN: 4294967295
            if (meta.bgp_info.extended_community_value == 65) { // Value: 65
                meta.valid_rt_community = 1; // Valid RT
            }
        }

        // Validate Site of Origin (SoO)
        if (meta.bgp_info.extended_community_asn <= 0xFFFFFFFF) { // Max valid ASN: 4294967295
            if (meta.bgp_info.extended_community_value == 65) { // Value: 65
                meta.valid_soo_community = 1; // Valid SoO
            }
        }

        // Drop invalid communities
        if (meta.valid_rt_community == 0 || meta.valid_soo_community == 0) {
            drop();
        } else {
            forward();
        }
    }
}

control egress {
    apply {
        // Optional egress processing
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
