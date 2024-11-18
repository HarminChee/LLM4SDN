// Define headers for Ethernet and IPv4
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

// Metadata to track routing information and BGP session state
struct metadata {
    bit<9> ingress_port;
    bit<9> egress_port;
    bit<32> as_path[10];  // Store the AS path (up to 10 ASNs)
    bit<32> local_asn;     // Local ASN for the router
    bit<32> peer_asn;      // ASN of the peer
    bit<1>  is_ibgp;       // Flag to indicate iBGP session
}

// Define parser to extract Ethernet and IPv4 packets
parser MyParser(packet_in pkt,
                out ethernet_t ethernet,
                out ipv4_t ipv4) {
    state start {
        pkt.extract(ethernet);
        transition select(ethernet.etherType) {
            0x0800: parse_ipv4;  // IPv4 packet
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(ipv4);
        transition accept;
    }
}

// Table for routing based on IPv4 destination address
table ipv4_lpm {
    key = {
        ipv4.dstAddr: lpm;
    }
    actions = {
        drop;
        ipv4_forward;
    }
    size = 1024;
    default_action = drop();
}

// Action to forward IPv4 packets
action ipv4_forward(bit<9> port) {
    standard_metadata.egress_spec = port;
}

// BGP AS path validation: Check if the AS path is valid for the session type (iBGP or eBGP)
action check_as_path(bit<32> peer_asn, bit<32> local_asn, bit<1> is_ibgp) {
    if (is_ibgp == 1) {
        // iBGP: AS check is relaxed, allow forwarding
    } else {
        // eBGP: AS path must not contain the local ASN
        for (int i = 0; i < 10; i++) {
            if (metadata.as_path[i] == local_asn) {
                // Drop the route if the local ASN is in the AS path (loop prevention)
                drop();
            }
        }
    }
}

// Apply control block
control MyIngress(inout ethernet_t ethernet,
                  inout ipv4_t ipv4,
                  inout metadata meta) {

    apply {
        // L3 routing based on destination IP
        ipv4_lpm.apply();

        // Check BGP AS path for eBGP sessions
        if (meta.is_ibgp == 0) {
            check_as_path(meta.peer_asn, meta.local_asn, meta.is_ibgp);
        }
    }
}

// Define the deparser to serialize the packet before sending
control MyDeparser(packet_out pkt,
                   in ethernet_t ethernet,
                   in ipv4_t ipv4) {
    apply {
        pkt.emit(ethernet);
        pkt.emit(ipv4);
    }
}

// Define the top-level architecture
control MyControl {
    MyParser() parser;
    MyIngress() ingress;
    MyDeparser() deparser;
}
