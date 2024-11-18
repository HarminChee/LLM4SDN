// Define headers for Ethernet, IPv4, MPLS, and VLAN
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

header mpls_t {
    bit<20> label;
    bit<3>  exp;
    bit<1>  bos;
    bit<8>  ttl;
}

header vlan_t {
    bit<12> vlan_id;
    bit<3>  priority;
    bit<1>  cfi;
}

// Metadata to track VRF and MPLS
struct metadata {
    bit<9> ingress_port;
    bit<9> egress_port;
    bit<32> vrf_id;
}

// Define parser to extract Ethernet, MPLS, and IPv4 packets
parser MyParser(packet_in pkt,
                out ethernet_t ethernet,
                out mpls_t mpls,
                out ipv4_t ipv4) {
    state start {
        pkt.extract(ethernet);
        transition select(ethernet.etherType) {
            0x8847: parse_mpls;  // MPLS unicast
            0x0800: parse_ipv4;  // IPv4 packet
            default: accept;
        }
    }

    state parse_mpls {
        pkt.extract(mpls);
        transition accept;
    }

    state parse_ipv4 {
        pkt.extract(ipv4);
        transition accept;
    }
}

// Table to route based on IPv4 destination address and VRF
table ipv4_lpm {
    key = {
        metadata.vrf_id: exact;
        ipv4.dstAddr: lpm;
    }
    actions = {
        drop;
        ipv4_forward;
    }
    size = 1024;
    default_action = drop();
}

// Table to handle MPLS forwarding
table mpls_lpm {
    key = {
        mpls.label: exact;
    }
    actions = {
        drop;
        mpls_forward;
    }
    size = 1024;
    default_action = drop();
}

// Action to forward IPv4 packets
action ipv4_forward(bit<9> port) {
    standard_metadata.egress_spec = port;
}

// Action to forward MPLS packets
action mpls_forward(bit<9> port) {
    standard_metadata.egress_spec = port;
}

// Apply control block
control MyIngress(inout ethernet_t ethernet,
                  inout mpls_t mpls,
                  inout ipv4_t ipv4,
                  inout metadata meta) {

    apply {
        // If MPLS is present, use MPLS table
        if (ethernet.etherType == 0x8847) {
            mpls_lpm.apply();
        } else if (ethernet.etherType == 0x0800) {
            // IPv4 routing based on destination IP and VRF
            ipv4_lpm.apply();
        }
    }
}

// Define the deparser to serialize the packet before sending
control MyDeparser(packet_out pkt,
                   in ethernet_t ethernet,
                   in mpls_t mpls,
                   in ipv4_t ipv4) {
    apply {
        pkt.emit(ethernet);
        if (ethernet.etherType == 0x8847) {
            pkt.emit(mpls);
        } else if (ethernet.etherType == 0x0800) {
            pkt.emit(ipv4);
        }
    }
}

// Define the top-level architecture
control MyControl {
    MyParser() parser;
    MyIngress() ingress;
    MyDeparser() deparser;
}
