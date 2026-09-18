-- Canonical model (P2-05, docs/contracts/canonical-model.md). PostgreSQL
-- Serverless v2, applied through the RDS Data API (CLAUDE.md #6).

CREATE TYPE entity_type AS ENUM (
    'resource', 'application', 'pipeline', 'repository', 'identity',
    'image', 'platform_tooling', 'governance', 'shared_infrastructure'
);

CREATE TYPE identity_key_type AS ENUM (
    'arn', 'instance_id', 'ssm_node_id', 'resource_id', 'ip', 'eni',
    'hostname', 'image_digest', 'pod_uid'
);

CREATE TYPE relation_type AS ENUM (
    'member_of', 'depends_on', 'deploys_to', 'built_from', 'runs_image',
    'operational_automation', 'managed_by_iac'
);

CREATE TYPE validation_status AS ENUM (
    'issued', 'confirmed', 'corrected', 'reassigned', 'partial',
    'no_response', 'escalated', 'signed_off'
);

CREATE TYPE run_status AS ENUM ('running', 'succeeded', 'failed');

CREATE TABLE run (
    run_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    started_at  timestamptz NOT NULL,
    finished_at timestamptz,
    status      run_status NOT NULL DEFAULT 'running'
);

CREATE TABLE entity (
    entity_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type entity_type NOT NULL,
    natural_key text NOT NULL,
    first_seen  timestamptz NOT NULL,
    last_seen   timestamptz NOT NULL,
    UNIQUE (entity_type, natural_key)
);

CREATE TABLE identity_link (
    link_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_id  uuid NOT NULL REFERENCES entity (entity_id),
    key_type   identity_key_type NOT NULL,
    key_value  text NOT NULL,
    tier       smallint NOT NULL,
    confidence numeric NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    UNIQUE (key_type, key_value)
);

CREATE INDEX identity_link_entity_id_idx ON identity_link (entity_id);

-- Bitemporal: observed_at/recorded_at track when the fact was true vs. when
-- the platform learned it; valid_from/valid_to track supersession by a later
-- assertion on the same (entity_id, attribute).
CREATE TABLE assertion (
    assertion_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_id    uuid NOT NULL REFERENCES entity (entity_id),
    attribute    text NOT NULL,
    value        jsonb NOT NULL,
    source       text NOT NULL,
    confidence   numeric NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    observed_at  timestamptz NOT NULL,
    recorded_at  timestamptz NOT NULL DEFAULT now(),
    valid_from   timestamptz NOT NULL,
    valid_to     timestamptz,
    run_id       uuid NOT NULL REFERENCES run (run_id)
);

CREATE INDEX assertion_entity_id_idx ON assertion (entity_id);
CREATE INDEX assertion_current_idx ON assertion (entity_id, attribute) WHERE valid_to IS NULL;

CREATE TABLE relation (
    relation_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    from_entity   uuid NOT NULL REFERENCES entity (entity_id),
    to_entity     uuid NOT NULL REFERENCES entity (entity_id),
    relation_type relation_type NOT NULL,
    confidence    numeric NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    source        text NOT NULL,
    valid_from    timestamptz NOT NULL,
    valid_to      timestamptz
);

CREATE INDEX relation_from_entity_idx ON relation (from_entity);
CREATE INDEX relation_to_entity_idx ON relation (to_entity);

CREATE TABLE evidence (
    evidence_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    derived_table  text NOT NULL,
    derived_id     uuid NOT NULL,
    raw_s3_uri     text NOT NULL,
    raw_line       integer NOT NULL,
    payload_sha256 text NOT NULL CHECK (payload_sha256 ~ '^[0-9a-f]{64}$')
);

CREATE INDEX evidence_derived_idx ON evidence (derived_table, derived_id);

-- Seeded with the confidence ladder in CLAUDE.md section 7.
CREATE TABLE source_precedence (
    signal     text PRIMARY KEY,
    confidence numeric NOT NULL CHECK (confidence BETWEEN 0 AND 1)
);

INSERT INTO source_precedence (signal, confidence) VALUES
    ('cloudformation_or_tfstate_membership', 0.95),
    ('runtime_primitive', 0.90),
    ('pipeline_deploy_target', 0.85),
    ('resource_group_or_tag', 0.75),
    ('flow_logs_fallback', 0.50);

CREATE TABLE adjudication (
    item_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind        text NOT NULL,
    candidates  jsonb NOT NULL,
    status      text NOT NULL,
    decided_by  text,
    decided_at  timestamptz
);

CREATE TABLE validation_state (
    entity_id       uuid PRIMARY KEY REFERENCES entity (entity_id),
    app_entity_id   uuid REFERENCES entity (entity_id),
    status          validation_status NOT NULL,
    response        jsonb,
    workbook_version text NOT NULL,
    row_hash        text NOT NULL,
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE finding (
    finding_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id               text NOT NULL,
    entity_id             uuid NOT NULL REFERENCES entity (entity_id),
    severity               text NOT NULL,
    value_usd              numeric NOT NULL,
    band_low                numeric NOT NULL,
    band_expected           numeric NOT NULL,
    band_high               numeric NOT NULL,
    band_assumption         text NOT NULL,
    realization_lag_days    integer NOT NULL,
    evidence_ids            uuid[] NOT NULL,
    run_id                  uuid NOT NULL REFERENCES run (run_id)
);

CREATE INDEX finding_entity_id_idx ON finding (entity_id);
CREATE INDEX finding_rule_id_idx ON finding (rule_id);
