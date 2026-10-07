import asyncio
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.enums import UserRole
from app.core.security import get_password_hash


async def create_staff():
    async with AsyncSessionLocal() as session:
        res = await session.execute(select(User).where(User.username == "staff"))
        existing = res.scalar_one_or_none()
        if existing:
            existing.password_hash = get_password_hash("Staff@12345")
            existing.role = UserRole.staff
            existing.full_name = "Warehouse Staff"
            existing.is_active = True
            await session.commit()
            print("Staff user 'staff' already exists. Password reset to 'Staff@12345'.")
        else:
            staff_user = User(
                username="staff",
                full_name="Warehouse Staff",
                password_hash=get_password_hash("Staff@12345"),
                role=UserRole.staff,
                is_active=True,
            )
            session.add(staff_user)
            await session.commit()
            print("Default staff user 'staff' created with password 'Staff@12345'.")


if __name__ == "__main__":
    asyncio.run(create_staff())
