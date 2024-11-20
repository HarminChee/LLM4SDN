// P4 Program for BGP Graceful Restart (GR) with iBGP Peering
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

header bgp_graceful_restart_t {
    bit<1> gr_enabled;       // 1 if Graceful Restart is enabled
    bit<1> r_bit;            // 1 if the router is in 'Restarting' state
    bit<1> f_bit;            // 1 if the router is in 'Forwarding' state
    bit<16> restart_time;    // Graceful Restart timer in seconds
    bit<1> global_mode;      // Global mode: 0 = Helper, 1 = Restarting
    bit<1> per_peer_mode;    // Per-peer mode: 0 = Disabled, 1 = Helper, 2 = Restarting
}

header bgp_t {
    bit<16> as_number;       // Autonomous System number
    ipv4_addr next_hop;      // Next-hop IP address
    bit<32> metric;          // Metric for the route
    ipv4_addr advertised_prefix; // Advertised prefix
}

struct metadata_t {
    bgp_graceful_restart_t gr_info;
    bgp_t bgp_info;
    bit<1> valid_route;         // Flag to check if the route is valid
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
        // Check if Graceful Restart is enabled
        if (meta.gr_info.gr_enabled == 1) {
            // Handle Graceful Restart state (Restarting/Forwarding)
            if (meta.gr_info.r_bit == 1) {
                // Graceful Restart is in Restarting state, keep the route in the RIB
                meta.valid_route = 1;
            } else if (meta.gr_info.f_bit == 1) {
                // Graceful Restart is in Forwarding state, keep forwarding the traffic
                meta.valid_route = 1;
            } else {
                // Graceful Restart is disabled, drop the route
                drop();
            }
        } else {
            // Graceful Restart is not enabled, process the route normally
            meta.valid_route = 1;
        }

        // Forward the packet if the route is valid
        if (meta.valid_route == 1) {
            forward();
        } else {
            drop();
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
