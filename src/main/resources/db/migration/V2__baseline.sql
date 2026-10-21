SET search_path TO app, extensions, public;

CREATE TABLE inspections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    inspection_code varchar(50) NOT NULL UNIQUE,
    property_id uuid NOT NULL,
    booking_id uuid,
    inspection_type varchar(32) NOT NULL,
    status varchar(24) NOT NULL DEFAULT 'PENDING',
    inspected_by_admin_user_id uuid,
    scheduled_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    notes varchar(3000),
    source_event_id uuid UNIQUE,
    version bigint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_inspection_type CHECK (inspection_type IN ('POST_CHECKOUT', 'PRE_CHECKIN', 'ROUTINE', 'MAINTENANCE', 'OWNER_HANDOVER', 'RETURN_TO_OWNER')),
    CONSTRAINT ck_inspection_status CHECK (status IN ('PENDING', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT ck_inspection_timeline CHECK (
        (started_at IS NULL OR scheduled_at IS NULL OR started_at >= scheduled_at)
        AND (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
    ),
    CONSTRAINT ck_inspection_completion CHECK ((status = 'COMPLETED' AND completed_at IS NOT NULL) OR status <> 'COMPLETED')
);
CREATE INDEX ix_inspection_property ON inspections(property_id, scheduled_at DESC);
CREATE INDEX ix_inspection_queue ON inspections(status, scheduled_at);

-- asset_id belongs to Property Service. Snapshot fields preserve what was
-- inspected even if the asset catalog changes later.
CREATE TABLE inspection_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    inspection_id uuid NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
    asset_id uuid,
    asset_name_snapshot varchar(180),
    area_or_component varchar(180),
    expected_quantity numeric(12,2),
    actual_quantity numeric(12,2),
    result varchar(24) NOT NULL,
    notes varchar(2000),
    checked_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_inspection_item_subject CHECK (asset_id IS NOT NULL OR area_or_component IS NOT NULL),
    CONSTRAINT ck_inspection_item_quantities CHECK (
        (expected_quantity IS NULL OR expected_quantity >= 0)
        AND (actual_quantity IS NULL OR actual_quantity >= 0)
    ),
    CONSTRAINT ck_inspection_item_result CHECK (result IN ('NORMAL', 'WORN', 'DAMAGED', 'MISSING', 'NOT_APPLICABLE', 'NOT_CHECKED')),
    UNIQUE NULLS NOT DISTINCT (inspection_id, asset_id, area_or_component)
);

CREATE TABLE incidents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_code varchar(50) NOT NULL UNIQUE,
    property_id uuid NOT NULL,
    asset_id uuid,
    inspection_id uuid REFERENCES inspections(id) ON DELETE SET NULL,
    inspection_item_id uuid REFERENCES inspection_items(id) ON DELETE SET NULL,
    booking_id uuid,
    incident_type varchar(32) NOT NULL,
    title varchar(240) NOT NULL,
    description varchar(4000) NOT NULL,
    area_or_component varchar(180),
    severity varchar(16) NOT NULL DEFAULT 'MEDIUM',
    status varchar(24) NOT NULL DEFAULT 'OPEN',
    responsibility varchar(24) NOT NULL DEFAULT 'UNKNOWN',
    reported_by_admin_user_id uuid,
    reported_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    resolution_summary varchar(2000),
    version bigint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_incident_subject CHECK (asset_id IS NOT NULL OR area_or_component IS NOT NULL),
    CONSTRAINT ck_incident_type CHECK (incident_type IN ('DAMAGE', 'MALFUNCTION', 'MISSING', 'WEAR_AND_TEAR', 'SAFETY', 'CLEANLINESS', 'OTHER')),
    CONSTRAINT ck_incident_severity CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    CONSTRAINT ck_incident_status CHECK (status IN ('OPEN', 'INVESTIGATING', 'IN_REPAIR', 'RESOLVED', 'CLOSED', 'REJECTED')),
    CONSTRAINT ck_incident_responsibility CHECK (responsibility IN ('UNKNOWN', 'HOST', 'VISTAY', 'GUEST', 'BUILDING', 'VENDOR', 'SHARED')),
    CONSTRAINT ck_incident_resolution CHECK ((status IN ('RESOLVED', 'CLOSED') AND resolved_at IS NOT NULL) OR status NOT IN ('RESOLVED', 'CLOSED'))
);
CREATE INDEX ix_incident_property_queue ON incidents(property_id, status, severity, reported_at DESC);
CREATE INDEX ix_incident_asset ON incidents(asset_id, reported_at DESC) WHERE asset_id IS NOT NULL;

CREATE TABLE work_orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_code varchar(50) NOT NULL UNIQUE,
    property_id uuid NOT NULL,
    asset_id uuid,
    incident_id uuid REFERENCES incidents(id) ON DELETE SET NULL,
    booking_id uuid,
    work_type varchar(32) NOT NULL,
    title varchar(240) NOT NULL,
    description varchar(4000),
    priority varchar(16) NOT NULL DEFAULT 'NORMAL',
    status varchar(24) NOT NULL DEFAULT 'NEW',
    assigned_admin_user_id uuid,
    assigned_team_id uuid,
    due_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    resolution_notes varchar(3000),
    estimated_cost numeric(19,4),
    actual_cost numeric(19,4),
    currency char(3) NOT NULL DEFAULT 'VND',
    created_by_admin_user_id uuid,
    version bigint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_work_order_type CHECK (work_type IN ('CLEANING', 'REPAIR', 'INSPECTION', 'PREVENTIVE_MAINTENANCE', 'REPLACEMENT', 'GUEST_ASSISTANCE')),
    CONSTRAINT ck_work_order_priority CHECK (priority IN ('LOW', 'NORMAL', 'HIGH', 'URGENT')),
    CONSTRAINT ck_work_order_status CHECK (status IN ('NEW', 'DISPATCH_PENDING', 'ASSIGNED', 'ACCEPTED', 'IN_PROGRESS', 'COMPLETED', 'VERIFIED', 'REJECTED', 'CANCELLED')),
    CONSTRAINT ck_work_order_costs CHECK ((estimated_cost IS NULL OR estimated_cost >= 0) AND (actual_cost IS NULL OR actual_cost >= 0)),
    CONSTRAINT ck_work_order_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_work_order_timeline CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at),
    CONSTRAINT ck_work_order_completion CHECK ((status IN ('COMPLETED', 'VERIFIED') AND completed_at IS NOT NULL) OR status NOT IN ('COMPLETED', 'VERIFIED'))
);
CREATE INDEX ix_work_order_queue ON work_orders(status, priority, due_at);
CREATE INDEX ix_work_order_property ON work_orders(property_id, status, created_at DESC);
CREATE INDEX ix_work_order_incident ON work_orders(incident_id) WHERE incident_id IS NOT NULL;

CREATE TABLE work_order_costs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id uuid NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
    cost_type varchar(24) NOT NULL,
    cost_stage varchar(16) NOT NULL,
    description varchar(500) NOT NULL,
    amount numeric(19,4) NOT NULL,
    currency char(3) NOT NULL DEFAULT 'VND',
    vendor_id uuid,
    incurred_on date,
    finance_expense_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_work_order_cost_type CHECK (cost_type IN ('PARTS', 'LABOR', 'SERVICE', 'TRANSPORT', 'MATERIAL', 'OTHER')),
    CONSTRAINT ck_work_order_cost_stage CHECK (cost_stage IN ('ESTIMATE', 'ACTUAL')),
    CONSTRAINT ck_work_order_cost_amount CHECK (amount > 0),
    CONSTRAINT ck_work_order_cost_currency CHECK (currency ~ '^[A-Z]{3}$')
);
CREATE INDEX ix_work_order_cost_timeline ON work_order_costs(work_order_id, incurred_on);

CREATE TABLE asset_condition_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id uuid NOT NULL,
    asset_id uuid NOT NULL,
    inspection_item_id uuid REFERENCES inspection_items(id) ON DELETE SET NULL,
    incident_id uuid REFERENCES incidents(id) ON DELETE SET NULL,
    work_order_id uuid REFERENCES work_orders(id) ON DELETE SET NULL,
    condition varchar(24) NOT NULL,
    quantity numeric(12,2),
    notes varchar(2000),
    recorded_by_admin_user_id uuid,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_asset_condition_subject CHECK (num_nonnulls(inspection_item_id, incident_id, work_order_id) >= 1),
    CONSTRAINT ck_asset_condition_value CHECK (condition IN ('UNKNOWN', 'NEW', 'GOOD', 'WORN', 'DAMAGED', 'MISSING', 'UNDER_REPAIR', 'DISPOSED')),
    CONSTRAINT ck_asset_condition_quantity CHECK (quantity IS NULL OR quantity >= 0)
);
CREATE INDEX ix_asset_condition_timeline ON asset_condition_events(asset_id, recorded_at DESC);

CREATE TABLE incident_status_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id uuid NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
    previous_status varchar(24),
    new_status varchar(24) NOT NULL,
    reason varchar(1000),
    actor_admin_user_id uuid,
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_incident_status_history ON incident_status_history(incident_id, occurred_at);

CREATE TABLE work_order_status_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id uuid NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
    previous_status varchar(24),
    new_status varchar(24) NOT NULL,
    reason varchar(1000),
    actor_admin_user_id uuid,
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_work_order_status_history ON work_order_status_history(work_order_id, occurred_at);

CREATE TABLE operations_media (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_type varchar(24) NOT NULL,
    subject_id uuid NOT NULL,
    media_id uuid NOT NULL,
    media_role varchar(32) NOT NULL,
    caption varchar(500),
    display_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_operations_media_subject CHECK (subject_type IN ('INSPECTION', 'INSPECTION_ITEM', 'INCIDENT', 'WORK_ORDER', 'ASSET_CONDITION')),
    CONSTRAINT ck_operations_media_role CHECK (media_role IN ('EVIDENCE', 'BEFORE', 'AFTER', 'DOCUMENT', 'OTHER')),
    UNIQUE (subject_type, subject_id, media_id)
);
CREATE INDEX ix_operations_media_subject ON operations_media(subject_type, subject_id, display_order);

-- Adapter state for the external employee/task system. A work order remains
-- the ViStay source of truth; the external system owns assignment execution.
CREATE TABLE work_order_dispatches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id uuid NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
    external_system varchar(80) NOT NULL,
    external_work_order_id varchar(180),
    idempotency_key varchar(160) NOT NULL UNIQUE,
    status varchar(24) NOT NULL DEFAULT 'PENDING',
    attempt_count integer NOT NULL DEFAULT 0,
    next_retry_at timestamptz,
    last_attempt_at timestamptz,
    last_error text,
    dispatched_at timestamptz,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_work_dispatch_status CHECK (status IN ('PENDING', 'SENDING', 'DISPATCHED', 'ACCEPTED', 'IN_PROGRESS', 'COMPLETED', 'FAILED', 'CANCELLED')),
    CONSTRAINT ck_work_dispatch_attempts CHECK (attempt_count >= 0),
    UNIQUE (external_system, external_work_order_id)
);
CREATE INDEX ix_work_dispatch_retry ON work_order_dispatches(status, next_retry_at) WHERE status IN ('PENDING', 'FAILED');

CREATE TABLE external_callback_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    external_system varchar(80) NOT NULL,
    external_event_id varchar(180) NOT NULL,
    external_work_order_id varchar(180) NOT NULL,
    event_type varchar(100) NOT NULL,
    payload_sha256 char(64) NOT NULL,
    status varchar(24) NOT NULL DEFAULT 'RECEIVED',
    received_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz,
    processing_error text,
    UNIQUE (external_system, external_event_id),
    CONSTRAINT ck_external_callback_status CHECK (status IN ('RECEIVED', 'PROCESSED', 'IGNORED', 'FAILED', 'QUARANTINED'))
);

CREATE TABLE processed_events (
    event_id uuid NOT NULL,
    consumer_name varchar(120) NOT NULL,
    processed_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id, consumer_name)
);

CREATE TABLE outbox_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type varchar(100) NOT NULL,
    aggregate_id uuid NOT NULL,
    aggregate_version bigint NOT NULL CHECK (aggregate_version >= 0),
    event_type varchar(160) NOT NULL,
    event_version integer NOT NULL DEFAULT 1 CHECK (event_version > 0),
    payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    available_at timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz,
    publish_attempts integer NOT NULL DEFAULT 0 CHECK (publish_attempts >= 0),
    last_error text,
    correlation_id varchar(100),
    causation_id varchar(100)
);
CREATE INDEX ix_operations_outbox_pending ON outbox_events(available_at, occurred_at) WHERE published_at IS NULL;

CREATE TABLE audit_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_admin_user_id uuid,
    action varchar(100) NOT NULL,
    aggregate_type varchar(100) NOT NULL,
    aggregate_id uuid NOT NULL,
    changes jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(changes) = 'object'),
    correlation_id varchar(100),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_operations_audit_aggregate ON audit_events(aggregate_type, aggregate_id, created_at DESC);
