control ingress {
    action ipv4_forward() {
        modify_field(standard_metadata.egress_spec, 1); // Define egress port
    }
    
    table bgp_table {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            ipv4_forward;
            drop;
        }
        size = 1024;
        default_action = drop;
    }

    action eigrp_forward() {
        modify_field(standard_metadata.egress_spec, 2);
    }

    table eigrp_table {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            eigrp_forward;
            drop;
        }
        size = 1024;
        default_action = drop;
    }

    apply {
        if (hdr.ipv4.isValid()) {
            bgp_table.apply();
            eigrp_table.apply();
        } else {
            drop();
        }
    }
}

control egress {
    apply {
        // Additional processing for outgoing packets
    }
}
