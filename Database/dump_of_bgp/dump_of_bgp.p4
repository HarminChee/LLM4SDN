#include <core.p4>

control ingress {
    action forward(port) {
        standard_metadata.egress_spec = port;
    }

    table routing {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            forward;
            drop;
        }
        size = 1024;
    }

    apply {
        if (hdr.ipv4.isValid()) {
            routing.apply();
        }
    }
}

control egress {
    apply { /* Add any egress processing if needed */ }
}

control MySwitchIngress {
    ingress ingress();
    egress egress();
}

package MySwitch(ingress, egress);

MySwitch(MySwitchIngress(), MySwitchIngress());
