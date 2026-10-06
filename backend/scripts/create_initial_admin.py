import argparse
import asyncio
import sys

from sqlalchemy import select

from app.core.security import get_password_hash
from app.database import AsyncSessionLocal
from app.models.enums import UserRole
from app.models.user import User


async def create_admin(username: str, full_name: str, password: str):
    async with AsyncSessionLocal() as session:
        result = await session.execute(select(User).where(User.username == username))
        existing_user = result.scalar_one_or_none()

        if existing_user:
            print(f"User '{username}' already exists. Updating role to admin and resetting password...")
            existing_user.password_hash = get_password_hash(password)
            existing_user.role = UserRole.admin
            existing_user.full_name = full_name
            existing_user.is_active = True
            await session.commit()
            print(f"Admin '{username}' updated successfully.")
            return

        new_admin = User(
            username=username,
            full_name=full_name,
            password_hash=get_password_hash(password),
            role=UserRole.admin,
            is_active=True,
        )
        session.add(new_admin)
        await session.commit()
        print(f"Admin user '{username}' created successfully!")


def main():
    parser = argparse.ArgumentParser(description="Create initial Admin user for Godown Management System")
    parser.add_argument("--username", default="admin", help="Admin username (default: admin)")
    parser.add_argument("--name", default="System Administrator", help="Admin full name")
    parser.add_argument("--password", default="Admin@12345", help="Admin password")

    args = parser.parse_args()
    asyncio.run(create_admin(args.username, args.name, args.password))


if __name__ == "__main__":
    main()