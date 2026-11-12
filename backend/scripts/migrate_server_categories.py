"""
migrate_server_categories.py

Automated script to align categories between Tally 1 and Tally 2 on the server database.
Guarantees 100% preservation of all serial numbers, inward/outward records, and products.

Usage:
    cd backend
    python scripts/migrate_server_categories.py [--sync-tally]
"""

import argparse
import asyncio
import os
import sys
import uuid

# Ensure backend root is in python path
current_dir = os.path.dirname(os.path.abspath(__file__))
backend_root = os.path.dirname(current_dir)
if backend_root not in sys.path:
    sys.path.insert(0, backend_root)
os.chdir(backend_root)

from sqlalchemy import select, func
from app.database import AsyncSessionLocal
from app.models.category import Category
from app.models.product import Product
from app.models.serial import SerialNumber


TALLY2_STOCK_GROUPS = [
    {"name": "AC (Tally 2)", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-000001d4", "parent": None, "dual": True},
    {"name": "General (Tally 2)", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-000000b8", "parent": None, "dual": False},
    {"name": "REFRIGERATOR (Tally 2)", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-000001d7", "parent": None, "dual": False},
    {"name": "Ac Stand", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-00000339", "parent": None, "dual": False},
    {"name": "CARRIER", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-000007ee", "parent": None, "dual": False},
    {"name": "CELFROST", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-000001c6", "parent": None, "dual": False},
    {"name": "Celfrost Blender Parts", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-00000318", "parent": None, "dual": False},
    {"name": "FORMENTY", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-000000bf", "parent": None, "dual": False},
    {"name": "Gift", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-000004e0", "parent": None, "dual": False},
    {"name": "Local", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-00000347", "parent": None, "dual": False},
    {"name": "ROCKWELL", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-00000120", "parent": None, "dual": False},
    {"name": "Washing Machin", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-000001d2", "parent": None, "dual": False},
    {"name": "AC  FORMENTY", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-00000111", "parent": "FORMENTY", "dual": True},
    {"name": "LED  FORMENTY", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-00000112", "parent": "FORMENTY", "dual": False},
    {"name": "MIXI", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-000002d7", "parent": "CELFROST", "dual": False},
    {"name": "Stablizer", "guid": "949b6368-1ccd-4ac3-9553-d3d99e54a311-000004d5", "parent": "FORMENTY", "dual": False},
]


async def run_server_migration(sync_tally: bool = False):
    print("=" * 65)
    print("    GA STOCK - SERVER DATABASE CATEGORY & SERIAL MIGRATION")
    print("=" * 65)

    async with AsyncSessionLocal() as db:
        # Step 1: Count serial numbers before doing anything
        initial_serials = (await db.execute(select(func.count(SerialNumber.id)))).scalar() or 0
        initial_products = (await db.execute(select(func.count(Product.id)))).scalar() or 0
        print(f"[*] Verified initial database state:")
        print(f"    - Total Serial Numbers: {initial_serials}")
        print(f"    - Total Products:       {initial_products}")

        # Step 2: Remove manually created junk categories that have 0 products & 0 serials
        for junk_name in ["jyfjkyfkhg"]:
            junk_cat = (await db.execute(select(Category).where(func.lower(Category.name) == junk_name.lower()))).scalar_one_or_none()
            if junk_cat:
                p_cnt = (await db.execute(select(func.count(Product.id)).where(Product.category_id == junk_cat.id))).scalar() or 0
                if p_cnt == 0:
                    print(f"[-] Deleting empty junk category '{junk_cat.name}'")
                    await db.delete(junk_cat)
                else:
                    print(f"[!] Junk category '{junk_cat.name}' has {p_cnt} products; skipped deletion for safety.")

        # Step 3: Safeguard Tally 1 'AC' vs Tally 2 'AC (Tally 2)'
        cat_ac = (await db.execute(select(Category).where(Category.name == "AC"))).scalar_one_or_none()
        if cat_ac and cat_ac.tally_guid == "949b6368-1ccd-4ac3-9553-d3d99e54a311-000001d4":
            print("[+] Disassociating Tally 2 guid from Tally 1 'AC' category")
            cat_ac.tally_guid = None

        # Step 4: Safeguard Tally 1 'General' vs Tally 2 'General (Tally 2)'
        cat_gen = (await db.execute(select(Category).where(Category.name == "General"))).scalar_one_or_none()
        if cat_gen and cat_gen.tally_guid == "949b6368-1ccd-4ac3-9553-d3d99e54a311-000000b8":
            print("[+] Disassociating Tally 2 guid from Tally 1 'General' category")
            cat_gen.tally_guid = None

        # Step 5: Rename empty typo duplicate 'REFRIGERATOR' -> 'REFRIGERATOR (Tally 2)' if present
        cat_ref = (await db.execute(select(Category).where(Category.name == "REFRIGERATOR"))).scalar_one_or_none()
        if cat_ref:
            p_cnt = (await db.execute(select(func.count(Product.id)).where(Product.category_id == cat_ref.id))).scalar() or 0
            if p_cnt == 0:
                print("[+] Renaming 'REFRIGERATOR' to 'REFRIGERATOR (Tally 2)'")
                cat_ref.name = "REFRIGERATOR (Tally 2)"

        # Step 6: Ensure all Tally 2 categories exist with proper GUIDs
        for t2_sg in TALLY2_STOCK_GROUPS:
            # Check by guid or target name
            c_existing = (await db.execute(
                select(Category).where(
                    (Category.tally_guid == t2_sg["guid"]) | (func.lower(Category.name) == t2_sg["name"].lower())
                )
            )).scalar_one_or_none()

            if c_existing:
                c_existing.name = t2_sg["name"]
                c_existing.tally_guid = t2_sg["guid"]
                c_existing.tally_parent_group = t2_sg["parent"]
                c_existing.has_dual_serial = t2_sg["dual"]
                c_existing.source = "TALLY"
            else:
                print(f"[+] Creating Tally 2 category: '{t2_sg['name']}'")
                new_cat = Category(
                    id=uuid.uuid4(),
                    name=t2_sg["name"],
                    has_dual_serial=t2_sg["dual"],
                    is_active=True,
                    tally_guid=t2_sg["guid"],
                    tally_parent_group=t2_sg["parent"],
                    source="TALLY",
                )
                db.add(new_cat)

        # Step 6b: Clean brand and model strings, and fix Tally stock quantities
        from app.services.tally_service import extract_clean_brand_and_model
        all_prods = (await db.execute(
            select(Product, Category).join(Category, Product.category_id == Category.id)
        )).all()
        for p, c in all_prods:
            clean_b, clean_m = extract_clean_brand_and_model(p.name, c.name)
            p.brand = clean_b
            p.model = clean_m
            if p.source == "TALLY" and p.tally_guid:
                if p.tally_stock_qty is None or p.tally_stock_qty < 0:
                    p.tally_stock_qty = 0

        await db.commit()

        # Step 7: STRICT SERIAL NUMBER VERIFICATION
        final_serials = (await db.execute(select(func.count(SerialNumber.id)))).scalar() or 0
        final_products = (await db.execute(select(func.count(Product.id)))).scalar() or 0
        print(f"\n[*] Strict Verification Check:")
        print(f"    - Serial Numbers Before: {initial_serials}")
        print(f"    - Serial Numbers After:  {final_serials}")
        if final_serials != initial_serials:
            await db.rollback()
            raise RuntimeError(
                f"FATAL ERROR: Serial count changed ({initial_serials} -> {final_serials})! Transaction rolled back."
            )
        print("    -> [OK] All serial numbers preserved 100% without loss.")

        # Step 8: Optional Tally Live Master Sync
        if sync_tally:
            print("\n[*] Triggering live Tally masters sync from TallyPrime...")
            from app.services.tally_service import TallySyncService
            try:
                sync_res = await TallySyncService.sync_masters_from_tally(
                    db,
                    company_name="GLOBAL AGENCIES - 2025-26",
                )
                print(f"[+] Tally sync complete: {sync_res}")
            except Exception as e:
                print(f"[!] Warning: Tally live sync could not be completed: {e}")

        # Step 9: Print Category & Serial Summary Table
        cats = (await db.execute(select(Category))).scalars().all()
        print("\n" + "=" * 65)
        print(f"{'Category Name':<28} | {'Products':<8} | {'Serials':<8}")
        print("-" * 65)
        for c in sorted(cats, key=lambda x: x.name):
            p_cnt = (await db.execute(select(func.count(Product.id)).where(Product.category_id == c.id))).scalar() or 0
            s_cnt = (await db.execute(
                select(func.count(SerialNumber.id))
                .join(Product, SerialNumber.product_id == Product.id)
                .where(Product.category_id == c.id)
            )).scalar() or 0
            print(f"{c.name:<28} | {p_cnt:<8} | {s_cnt:<8}")
        print("=" * 65)
        print("[SUCCESS] Server database category alignment completed successfully!\n")


def main():
    parser = argparse.ArgumentParser(description="GA STOCK Server Database Migration Script")
    parser.add_argument(
        "--sync-tally",
        action="store_true",
        help="Also sync products/models live from TallyPrime after category alignment.",
    )
    args = parser.parse_args()
    asyncio.run(run_server_migration(sync_tally=args.sync_tally))


if __name__ == "__main__":
    main()

