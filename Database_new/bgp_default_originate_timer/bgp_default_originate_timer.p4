// P4 Program for BGP Default-Originate with Timer Control
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

header bgp_default_t {
    bit<1> default_originate;     // 1 if default-originate is enabled
    bit<32> next_hop_ipv4;        // Next hop for IPv4 default route
    bit<32> timer;                // Timer for delaying default route advertisement
}

struct metadata_t {
    bgp_default_t bgp_default_info;
    bit<1> valid_route;           // Flag to check if the route is valid
    bit<1> timer_expired;         // 1 if the timer has expired, allowing route advertisement
    bit<32> current_time;         // Current time to compare with the timer
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
        // Check if the default-originate timer has expired
        if (hdr.ipv4.isValid()) {
            if (meta.bgp_default_info.default_originate == 1) {
                if (hdr.ipv4.dstAddr == 0x00000000) {  // Check for default route (0.0.0.0)
                    if (meta.current_time >= meta.bgp_default_info.timer) {
                        // Timer has expired, allow the route to be advertised
                        meta.timer_expired = 1;
                        forward(meta.bgp_default_info.next_hop_ipv4);
                    } else {
                        // Timer has not expired, drop the route advertisement
                        meta.timer_expired = 0;
                        drop();
                    }
                }
            }
        }
    }
}

control egress {
    apply {
        // Egress processing, if needed
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
