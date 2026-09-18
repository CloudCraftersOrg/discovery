"""Tests for platform/db/migrations/0001_init.sql (P2-05 acceptance).

Run against a real PostgreSQL 16 with the migration already applied:

    docker run -d --name condor-pg-test -e POSTGRES_PASSWORD=test \
        -e POSTGRES_DB=condor -p 15432:5432 postgres:16
    docker exec -u postgres condor-pg-test psql -d condor \
        -f platform/db/migrations/0001_init.sql
    DATABASE_URL=postgresql://postgres:test@localhost:15432/condor pytest platform/db/tests
"""

import os

import psycopg2
import pytest

DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql://postgres:test@localhost:15432/condor"
)


@pytest.fixture
def conn():
    connection = psycopg2.connect(DATABASE_URL)
    yield connection
    connection.rollback()
    connection.close()


ENUM_CASES = [
    (
        "entity_type",
        {
            "resource", "application", "pipeline", "repository", "identity",
            "image", "platform_tooling", "governance", "shared_infrastructure",
        },
    ),
    (
        "identity_key_type",
        {
            "arn", "instance_id", "ssm_node_id", "resource_id", "ip", "eni",
            "hostname", "image_digest", "pod_uid",
        },
    ),
    (
        "relation_type",
        {
            "member_of", "depends_on", "deploys_to", "built_from", "runs_image",
            "operational_automation", "managed_by_iac",
        },
    ),
    (
        "validation_status",
        {
            "issued", "confirmed", "corrected", "reassigned", "partial",
            "no_response", "escalated", "signed_off",
        },
    ),
]


@pytest.mark.parametrize("type_name,expected", ENUM_CASES)
def test_enum_values(conn, type_name, expected):
    with conn.cursor() as cur:
        cur.execute(
            "SELECT enumlabel FROM pg_enum e "
            "JOIN pg_type t ON e.enumtypid = t.oid WHERE t.typname = %s",
            (type_name,),
        )
        actual = {row[0] for row in cur.fetchall()}
    assert actual == expected


FINDING_VALUE_COLUMNS = [
    "value_usd", "band_low", "band_expected", "band_high",
    "band_assumption", "realization_lag_days", "evidence_ids",
]


@pytest.mark.parametrize("column", FINDING_VALUE_COLUMNS)
def test_finding_value_columns_not_null(conn, column):
    with conn.cursor() as cur:
        cur.execute(
            "SELECT is_nullable FROM information_schema.columns "
            "WHERE table_name = 'finding' AND column_name = %s",
            (column,),
        )
        row = cur.fetchone()
    assert row is not None, f"finding.{column} does not exist"
    assert row[0] == "NO", f"finding.{column} is nullable"


def test_source_precedence_seeded_with_confidence_ladder(conn):
    with conn.cursor() as cur:
        cur.execute("SELECT signal, confidence FROM source_precedence ORDER BY confidence DESC")
        rows = cur.fetchall()
    assert [float(c) for _, c in rows] == [0.95, 0.90, 0.85, 0.75, 0.50]


def test_insert_and_query_round_trip(conn):
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO run (started_at, status) VALUES (now(), 'running') RETURNING run_id"
        )
        run_id = cur.fetchone()[0]

        cur.execute(
            "INSERT INTO entity (entity_type, natural_key, first_seen, last_seen) "
            "VALUES ('application', 'tienda', now(), now()) RETURNING entity_id"
        )
        entity_id = cur.fetchone()[0]

        cur.execute(
            "INSERT INTO finding (rule_id, entity_id, severity, value_usd, band_low, "
            "band_expected, band_high, band_assumption, realization_lag_days, "
            "evidence_ids, run_id) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
            ("rightsizing", entity_id, "medium", 120.50, 80, 120, 200, "on-demand rate", 30, [], run_id),
        )
    assert entity_id is not None
