#include <core.p4>

control ingress {
    apply {
        // Match traffic from CE1 to CE2 through RT1 and RT2
        if (hdr.ipv4.srcAddr == 172.16.1.1 && hdr.ipv4.dstAddr == 172.16.1.2) {
            hdr.ipv4.ttl -= 1;
            standard_metadata.egress_spec = 2; // Forward to RT1's rt1-eth1
        }

        // Match traffic from CE2 to CE3 through RT2 and RT3
        if (hdr.ipv4.srcAddr == 172.16.1.2 && hdr.ipv4.dstAddr == 172.16.1.3) {
            hdr.ipv4.ttl -= 1;
            standard_metadata.egress_spec = 3; // Forward to RT2's rt2-eth1
        }

        // Match traffic from CE3 to CE1 through RT3 and RT1
        if (hdr.ipv4.srcAddr == 172.16.1.3 && hdr.ipv4.dstAddr == 172.16.1.1) {
            hdr.ipv4.ttl -= 1;
            standard_metadata.egress_spec = 1; // Forward to RT3's rt3-eth2
        }

        // MPLS Label Switching for LDP
        if (hdr.mpls.isValid()) {
            switch (hdr.mpls.label) {
                case 100: {
                    standard_metadata.egress_spec = 4; // Forward to RT1's rt1-eth2
                }
                case 200: {
                    standard_metadata.egress_spec = 5; // Forward to RT2's rt2-eth2
                }
                case 300: {
                    standard_metadata.egress_spec = 6; // Forward to RT3's rt3-eth1
                }
                default: {
                    drop();
                }
            }
        }
    }
}

control egress {
    apply {
        // Decrement TTL for all packets
        hdr.ipv4.ttl -= 1;
    }
}

parser MyParser(packet_in pkt, out headers hdr, inout standard_metadata_t standard_metadata) {
    state start {
        transition select(pkt.lookahead<ethernet_t>().etherType) {
            0x0800: parse_ipv4;
            0x8847: parse_mpls;
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition accept;
    }
    state parse_mpls {
        pkt.extract(hdr.mpls);
        transition accept;
    }
}

deparser MyDeparser(packet_out pkt, in headers hdr) {
    apply {
        pkt.emit(hdr.ethernet);
        if (hdr.mpls.isValid()) {
            pkt.emit(hdr.mpls);
        }
        pkt.emit(hdr.ipv4);
    }
}

control MyIngress = ingress();
control MyEgress = egress();
parser MyParser = MyParser();
deparser MyDeparser = MyDeparser();
