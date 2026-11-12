import asyncio
import os
import sys

# Ensure backend root in path
sys.path.insert(0, r"A:\GA STOCK\backend")
os.chdir(r"A:\GA STOCK\backend")

from sqlalchemy import select, func
from app.database import AsyncSessionLocal
from app.models.product import Product
from app.models.category import Category
from app.models.serial import SerialNumber
from app.services.tally_service import extract_clean_brand_and_model

async def clean_database_products():
    async with AsyncSessionLocal() as db:
        initial_serials = (await db.execute(select(func.count(SerialNumber.id)))).scalar()
        print(f"[*] Initial serials count: {initial_serials}")
        assert initial_serials == 2029, f"Unexpected serial count: {initial_serials}"

        prods = (await db.execute(
            select(Product, Category).join(Category, Product.category_id == Category.id)
        )).all()

        models_updated = 0
        stocks_updated = 0

        for p, c in prods:
            # 1. Clean brand and model
            clean_b, clean_m = extract_clean_brand_and_model(p.name, c.name)
            if clean_b != p.brand or clean_m != p.model:
                p.brand = clean_b
                p.model = clean_m
                models_updated += 1

            # 2. Clean Tally stock
            if p.source == "TALLY" and p.tally_guid:
                if p.tally_stock_qty is None:
                    p.tally_stock_qty = 0
                    stocks_updated += 1
                elif p.tally_stock_qty < 0:
                    p.tally_stock_qty = 0
                    stocks_updated += 1

        await db.commit()

        final_serials = (await db.execute(select(func.count(SerialNumber.id)))).scalar()
        print(f"[*] Final serials count: {final_serials}")
        assert final_serials == initial_serials, f"CRITICAL: Serials count changed!"

        print(f"[+] Successfully cleaned {models_updated} model/brand records.")
        print(f"[+] Successfully fixed {stocks_updated} Tally stock counts (defaulted to 0 / floored negative).")

if __name__ == "__main__":
    asyncio.run(clean_database_products())

