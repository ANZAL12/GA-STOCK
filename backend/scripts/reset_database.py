import asyncio
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from sqlalchemy import text
from app.database import engine, AsyncSessionLocal
from app.models import Base
from app.models.user import User
from app.models.enums import UserRole
from app.core.security import get_password_hash


async def reset_db():
    print("Beginning database reset...")
    
    # 1. Truncate all tables
    table_names = list(Base.metadata.tables.keys())
    print(f"Tables to truncate: {table_names}")
    
    async with engine.begin() as conn:
        tables_str = ", ".join(f'"{name}"' for name in table_names)
        sql = f"TRUNCATE TABLE {tables_str} RESTART IDENTITY CASCADE;"
        await conn.execute(text(sql))
        print("All application tables truncated with RESTART IDENTITY CASCADE.")

    # 2. Re-create default Admin and Staff users
    async with AsyncSessionLocal() as session:
        admin_user = User(
            username="admin",
            full_name="System Administrator",
            password_hash=get_password_hash("Admin@12345"),
            role=UserRole.admin,
            is_active=True,
        )
        staff_user = User(
            username="staff",
            full_name="Warehouse Staff",
            password_hash=get_password_hash("Staff@12345"),
            role=UserRole.staff,
            is_active=True,
        )
        session.add_all([admin_user, staff_user])
        await session.commit()
        print("Default users created:")
        print("  • Admin: username='admin', password='Admin@12345'")
        print("  • Staff: username='staff', password='Staff@12345'")

    print("\nDatabase is now completely fresh and ready!")


if __name__ == "__main__":
    asyncio.run(reset_db())
