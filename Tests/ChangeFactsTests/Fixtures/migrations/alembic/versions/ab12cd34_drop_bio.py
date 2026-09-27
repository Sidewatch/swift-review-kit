"""drop bio

Revision ID: ab12cd34
"""
from alembic import op
import sqlalchemy as sa

revision = "ab12cd34"
down_revision = "9f8e7d6c"


def upgrade():
    op.drop_column("profiles", "bio")
    op.alter_column("profiles", "age", type_=sa.String(8))
    op.execute("DELETE FROM sessions WHERE expires_at < now()")


def downgrade():
    pass
