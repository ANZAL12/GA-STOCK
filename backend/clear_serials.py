import asyncio
from sqlalchemy import text
from app.database import AsyncSessionLocal

async def clear_all_serial_entries():
    async with AsyncSessionLocal() as session:
        print("Clearing all serial-related records...")
        
        # 1. Serial history
        res = await session.execute(text("DELETE FROM serial_history"))
        print(f"Deleted serial_history: {res.rowcount} rows")

        # 2. Returns
        res = await session.execute(text("DELETE FROM returns"))
        print(f"Deleted returns: {res.rowcount} rows")

        # 3. Outward lines & batches
        res = await session.execute(text("DELETE FROM outward_lines"))
        print(f"Deleted outward_lines: {res.rowcount} rows")
        res = await session.execute(text("DELETE FROM outward_batches"))
        print(f"Deleted outward_batches: {res.rowcount} rows")

        # 4. Inward lines & batches
        res = await session.execute(text("DELETE FROM inward_lines"))
        print(f"Deleted inward_lines: {res.rowcount} rows")
        res = await session.execute(text("DELETE FROM inward_batches"))
        print(f"Deleted inward_batches: {res.rowcount} rows")

        # 5. Serial numbers
        res = await session.execute(text("DELETE FROM serial_numbers"))
        print(f"Deleted serial_numbers: {res.rowcount} rows")

        # 6. Reset product current stock quantities to opening_stock_qty and has_had_inward = False
        res = await session.execute(text("""
            UPDATE products 
            SET current_stock_qty = opening_stock_qty,
                has_had_inward = FALSE
        """))
        print(f"Reset product stock counts: {res.rowcount} products updated")

        await session.commit()
        print("Successfully committed transaction! All serial entries deleted.")

if __name__ == "__main__":
    asyncio.run(clear_all_serial_entries())
