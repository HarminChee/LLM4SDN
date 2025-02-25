// P4 Program for BGP Minimum Holdtime with Notification
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

header bgp_open_t {
    bit<16> as_number;         // Autonomous System number
    bit<16> hold_time;         // BGP hold time
    ipv4_addr neighbor_addr;   // Neighbor's IP address
}

header bgp_notification_t {
    bit<16> error_code;        // BGP Notification Error Code
    bit<16> sub_error_code;    // BGP Notification Sub Error Code
}

struct metadata_t {
    bgp_open_t bgp_open_info;
    bgp_notification_t bgp_notification_info;
    bit<1> valid_open_message;    // Flag to check if the BGP OPEN message is valid
    bit<1> unacceptable_holdtime; // Flag to check if the hold time is unacceptable
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

    state parse_bgp_open {
        pkt.extract(hdr.bgp_open_info);
        transition accept;
    }

    state parse_bgp_notification {
        pkt.extract(hdr.bgp_notification_info);
        transition accept;
    }
}

control ingress {
    apply {
        // Minimum hold time for R1
        bit<16> minimum_hold_time = 10;

        // Check if the BGP OPEN message is valid
        if (meta.bgp_open_info.as_number != 0) {
            meta.valid_open_message = 1;
        }

        // Check if the hold time is below the minimum required hold time
        if (meta.bgp_open_info.hold_time < minimum_hold_time) {
            meta.unacceptable_holdtime = 1;
            // Trigger BGP Notification (OPEN Message Error/Unacceptable Hold Time)
            meta.bgp_notification_info.error_code = 2; // OPEN Message Error
            meta.bgp_notification_info.sub_error_code = 6; // Unacceptable Hold Time
        } else {
            meta.unacceptable_holdtime = 0;
        }

        // Send BGP Notification if the hold time is unacceptable
        if (meta.valid_open_message == 1 && meta.unacceptable_holdtime == 1) {
            drop(); // Drop the BGP session and send a Notification
        } else {
            forward(); // Forward the packet if the session is valid
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
