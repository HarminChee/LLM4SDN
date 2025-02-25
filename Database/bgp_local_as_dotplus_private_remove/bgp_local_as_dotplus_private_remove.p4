// P4 Program for BGP Local-AS with Remove-Private-AS
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
    bit<16> as_number;         // Autonomous System number
    ipv4_addr advertised_prefix; // Advertised IPv4 prefix
    bit<16> aspath[16];        // AS path (array of AS numbers)
    bit<16> aspath_length;     // Length of the AS path
    bit<1> remove_private_as;  // Remove-private-AS flag
}

struct metadata_t {
    bgp_t bgp_info;
    bit<1> valid_route;         // Flag to check if the BGP route is valid
    bit<1> remove_private_as;   // Flag to check if remove-private-AS is enabled
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
        // Check if the advertised prefix is valid
        if (meta.bgp_info.advertised_prefix != 0) {
            meta.valid_route = 1;
        }

        // Check if remove-private-AS is enabled
        if (meta.bgp_info.remove_private_as == 1) {
            // Strip private ASNs (64512-65535)
            for (int i = 0; i < meta.bgp_info.aspath_length; i++) {
                if (meta.bgp_info.aspath[i] >= 64512 && meta.bgp_info.aspath[i] <= 65535) {
                    meta.bgp_info.aspath[i] = 0; // Remove private AS
                }
            }
        }

        // Forward the packet if the BGP route is valid
        if (meta.valid_route == 1) {
            forward();
        } else {
            drop(); // Drop the packet if the route is not valid
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
