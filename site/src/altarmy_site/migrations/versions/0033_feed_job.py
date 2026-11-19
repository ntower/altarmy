"""job_runs.job also allows 'feed': the hourly Blizzard auction feed (`altarmy-site feed`)

Additive: the previous release's instances never write the new value.

Revision ID: 0033
Revises: 0032
Create Date: 2026-11-19 12:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0033"
down_revision: str | None = "0032"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

OLD = "job IN ('ingest', 'merge', 'prune', 'ahledger')"
NEW = "job IN ('ingest', 'merge', 'prune', 'ahledger', 'feed')"
CONSTRAINT = "ck_job_runs_job"


def _set_jobs(old: str, new: str) -> None:
    """Swap the CHECK on job_runs.job; on SQLite by editing the stored table definition in place, as
    revision 0009 does (the stored rows stay valid either way, once a downgrade deleted the feed's)."""
    conn = op.get_bind()
    if conn.dialect.name != "sqlite":
        op.drop_constraint(op.f(CONSTRAINT), "job_runs", type_="check")
        op.create_check_constraint(op.f(CONSTRAINT), "job_runs", sa.text(new))
        return
    version = int(conn.exec_driver_sql("PRAGMA schema_version").scalar_one())
    conn.exec_driver_sql("PRAGMA writable_schema=ON")
    conn.execute(
        sa.text(
            "UPDATE sqlite_master SET sql = replace(sql, :old, :new) "
            "WHERE type = 'table' AND name = 'job_runs'"
        ),
        {"old": old, "new": new},
    )
    conn.exec_driver_sql(f"PRAGMA schema_version={version + 1}")
    conn.exec_driver_sql("PRAGMA writable_schema=OFF")


def upgrade() -> None:
    _set_jobs(OLD, NEW)


def downgrade() -> None:
    op.execute("DELETE FROM job_runs WHERE job = 'feed'")
    _set_jobs(NEW, OLD)
