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

// Metadata to track routing information and BGP communities
struct metadata {
    bit<9> ingress_port;
    bit<9> egress_port;
    bit<32> bgp_asn;                     // Store the BGP ASN
    bit<32> bgp_communities[2];          // Store two BGP community values
    bit<1>  community_list_matched;      // Flag to indicate if the community list is matched
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

// BGP community-list handling: Match communities based on the community list
action match_community_list(bit<32> communities[2]) {
    if ((communities[0] == 0xFE010001 && communities[1] == 0xFE020002) ||  // 65001:1 AND 65002:2
        (communities[0] == 0xFE010003 || communities[1] == 0xFE010003)) {  // 65001:3 (OR condition)
        // Set the flag to indicate the community-list matched
        metadata.community_list_matched = 1;
    }
}

// Apply control block
control MyIngress(inout ethernet_t ethernet,
                  inout ipv4_t ipv4,
                  inout metadata meta) {

    apply {
        // L3 routing based on destination IP
        ipv4_lpm.apply();

        // Check if the packet matches the BGP community list
        match_community_list(meta.bgp_communities);

        // Drop the packet if the community list is matched (i.e., it should be filtered)
        if (meta.community_list_matched == 1) {
            drop();
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
