#include <core.p4>
#include <v1model.p4>

typedef bit<128> ipv6_addr_t;

// Define headers
header ipv6_t {
    ipv6_addr_t src_addr;
    ipv6_addr_t dst_addr;
    bit<8> traffic_class;
    bit<20> flow_label;
    bit<8> hop_limit;
    bit<16> payload_len;
    bit<8> next_hdr;
}

header seg6_t {
    ipv6_addr_t seg_list[4]; // Segment Routing Header (SRH) with 4 segments
    bit<8> next_hdr;
    bit<8> hdr_ext_len;
    bit<8> segments_left;
}

// Define parser
parser MyParser(packet_in pkt,
                out ipv6_t ipv6_hdr,
                out seg6_t seg6_hdr) {
    state start {
        pkt.extract(ipv6_hdr);
        transition select(ipv6_hdr.next_hdr) {
            43: parse_seg6; // Segment Routing Header (SRH)
            default: accept;
        }
    }
    state parse_seg6 {
        pkt.extract(seg6_hdr);
        transition accept;
    }
}

// Define match-action tables
table ipv6_forward {
    key = {
        ipv6_t.dst_addr: exact;
    }
    actions = {
        send;
        drop;
    }
    size = 1024;
}

table srv6_process {
    key = {
        seg6_t.segments_left: exact;
    }
    actions = {
        decap_and_forward;
        forward_to_next_segment;
    }
    size = 1024;
}

// Define actions
action send(port_t port) {
    standard_metadata.egress_spec = port;
}

action drop() {
    mark_to_drop();
}

action decap_and_forward() {
    remove(seg6_t);
    ipv6_forward.apply();
}

action forward_to_next_segment() {
    seg6_t.segments_left = seg6_t.segments_left - 1;
    ipv6_t.dst_addr = seg6_t.seg_list[seg6_t.segments_left];
    ipv6_forward.apply();
}

// Define control blocks
control ingress {
    apply(ipv6_forward);
    apply(srv6_process);
}

control egress {
    // No additional processing in egress
}

control MyDeparser(packet_out pkt,
                   in ipv6_t ipv6_hdr,
                   in seg6_t seg6_hdr) {
    apply {
        pkt.emit(ipv6_hdr);
        pkt.emit(seg6_hdr);
    }
}

V1Switch(MyParser(), ingress(), egress(), MyDeparser()) main;
