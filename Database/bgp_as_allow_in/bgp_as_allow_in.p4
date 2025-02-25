// Define headers for Ethernet, IPv4, and IPv6
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

header ipv6_t {
    bit<4>  version;
    bit<8>  trafficClass;
    bit<20> flowLabel;
    bit<16> payloadLen;
    bit<8>  nextHeader;
    bit<8>  hopLimit;
    bit<128> srcAddr;
    bit<128> dstAddr;
}

// Metadata to track routing information and AS path validation
struct metadata {
    bit<9> ingress_port;
    bit<9> egress_port;
    bit<16> as_path_length;     // Store the AS path length
    bit<16> allowas_in_value;   // Store the BGP allowas-in value
}

// Define parser to extract Ethernet, IPv4, and IPv6 packets
parser MyParser(packet_in pkt,
                out ethernet_t ethernet,
                out ipv4_t ipv4,
                out ipv6_t ipv6) {
    state start {
        pkt.extract(ethernet);
        transition select(ethernet.etherType) {
            0x0800: parse_ipv4;  // IPv4 packet
            0x86DD: parse_ipv6;  // IPv6 packet
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(ipv4);
        transition accept;
    }

    state parse_ipv6 {
        pkt.extract(ipv6);
        transition accept;
    }
}

// Table for routing based on IPv4 or IPv6 destination address
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

table ipv6_lpm {
    key = {
        ipv6.dstAddr: lpm;
    }
    actions = {
        drop;
        ipv6_forward;
    }
    size = 1024;
    default_action = drop();
}

// Action to forward IPv4 packets
action ipv4_forward(bit<9> port) {
    standard_metadata.egress_spec = port;
}

// Action to forward IPv6 packets
action ipv6_forward(bit<9> port) {
    standard_metadata.egress_spec = port;
}

// BGP `allowas-in` handling: Check if AS path length is within the allowed limit
action allowas_in_check(bit<16> as_path_length, bit<16> allowas_in_value) {
    if (as_path_length <= allowas_in_value) {
        // Allow the route
    } else {
        // Drop the route (AS path length exceeds allowas-in value)
        drop();
    }
}

// Apply control block
control MyIngress(inout ethernet_t ethernet,
                  inout ipv4_t ipv4,
                  inout ipv6_t ipv6,
                  inout metadata meta) {

    apply {
        if (ethernet.etherType == 0x0800) {
            // IPv4 routing
            ipv4_lpm.apply();
        } else if (ethernet.etherType == 0x86DD) {
            // IPv6 routing
            ipv6_lpm.apply();
        }

        // Check AS path length against allowas-in value
        if (meta.as_path_length != 0 && meta.allowas_in_value != 0) {
            allowas_in_check(meta.as_path_length, meta.allowas_in_value);
        }
    }
}

// Define the deparser to serialize the packet before sending
control MyDeparser(packet_out pkt,
                   in ethernet_t ethernet,
                   in ipv4_t ipv4,
                   in ipv6_t ipv6) {
    apply {
        pkt.emit(ethernet);
        if (ethernet.etherType == 0x0800) {
            pkt.emit(ipv4);
        } else if (ethernet.etherType == 0x86DD) {
            pkt.emit(ipv6);
        }
    }
}

// Define the top-level architecture
control MyControl {
    MyParser() parser;
    MyIngress() ingress;
    MyDeparser() deparser;
}
