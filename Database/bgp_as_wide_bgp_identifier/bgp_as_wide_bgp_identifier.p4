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

// Metadata to track routing information and BGP identifier behavior
struct metadata {
    bit<9> ingress_port;
    bit<9> egress_port;
    bit<32> bgp_identifier;  // Store the BGP identifier
    bit<1> is_internal_bgp;  // Flag for identifying internal peers (iBGP)
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

// BGP identifier validation: Check if the BGP identifier is valid
action check_bgp_identifier(bit<32> bgp_identifier, bit<1> is_internal_bgp) {
    if (is_internal_bgp == 1 && bgp_identifier == 0) {
        // If internal BGP peer and invalid BGP identifier, drop the route
        drop();
    }
}

// Apply control block
control MyIngress(inout ethernet_t ethernet,
                  inout ipv4_t ipv4,
                  inout metadata meta) {

    apply {
        // L3 routing based on destination IP
        ipv4_lpm.apply();

        // Check BGP identifier for internal peers
        if (meta.is_internal_bgp == 1) {
            check_bgp_identifier(meta.bgp_identifier, meta.is_internal_bgp);
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
