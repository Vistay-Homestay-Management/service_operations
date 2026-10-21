package com.vistay.operations.adapter.in.graphql;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class ServiceInfoQueryTest {

    private final ServiceInfoQuery query = new ServiceInfoQuery();

    @Test
    void exposesStableServiceIdentity() {
        var info = query.operationsServiceInfo();

        assertThat(info.name()).isEqualTo("operations");
        assertThat(info.version()).isEqualTo("0.1.0");
    }
}

