import asyncio
from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.models.category import Category
from app.models.product import Product
from app.models.shop import Shop

DEFAULT_CATEGORIES = [
    "Television",
    "Refrigerator",
    "Washing Machine",
    "Air Conditioner",
]

SAMPLE_PRODUCTS = [
    {
        "category": "Television",
        "name": "Samsung 43 inch LED TV",
        "brand": "Samsung",
        "model": "UA43T5350",
        "size_capacity": "43 inch",
        "sku": "SAM-TV-43-01",
        "opening_stock_qty": 20,
    },
    {
        "category": "Refrigerator",
        "name": "LG 260 L Refrigerator",
        "brand": "LG",
        "model": "GL-T292RPZY",
        "size_capacity": "260 L",
        "sku": "LG-REF-260-01",
        "opening_stock_qty": 15,
    },
    {
        "category": "Washing Machine",
        "name": "IFB 7 kg Washing Machine",
        "brand": "IFB",
        "model": "Senorita SXS 7010",
        "size_capacity": "7 kg",
        "sku": "IFB-WM-7-01",
        "opening_stock_qty": 10,
    },
    {
        "category": "Air Conditioner",
        "name": "Voltas 1.5 Ton Split AC",
        "brand": "Voltas",
        "model": "183V Vectra Prism",
        "size_capacity": "1.5 Ton",
        "sku": "VOL-AC-15-01",
        "opening_stock_qty": 12,
    },
]

SAMPLE_SHOPS = [
    {
        "name": "Sree Electronics",
        "city": "Malappuram",
        "phone": "+91 98470 12345",
    },
    {
        "name": "City Home Appliances",
        "city": "Kozhikode",
        "phone": "+91 98471 23456",
    },
    {
        "name": "Royal Electronics",
        "city": "Manjeri",
        "phone": "+91 98472 34567",
    },
]


async def seed():
    async with AsyncSessionLocal() as session:
        cat_map = {}
        for cat_name in DEFAULT_CATEGORIES:
            res = await session.execute(select(Category).where(Category.name == cat_name))
            cat = res.scalar_one_or_none()
            if not cat:
                cat = Category(name=cat_name, is_active=True)
                session.add(cat)
                await session.flush()
                print(f"Created category: {cat_name}")
            else:
                print(f"Category already exists: {cat_name}")
            cat_map[cat_name] = cat.id

        for p in SAMPLE_PRODUCTS:
            res = await session.execute(select(Product).where(Product.name == p["name"]))
            prod = res.scalar_one_or_none()
            if not prod:
                qty = p["opening_stock_qty"]
                prod = Product(
                    name=p["name"],
                    brand=p["brand"],
                    model=p["model"],
                    size_capacity=p["size_capacity"],
                    sku=p["sku"],
                    category_id=cat_map[p["category"]],
                    opening_stock_qty=qty,
                    current_stock_qty=qty,
                    has_had_inward=False,
                    is_active=True,
                )
                session.add(prod)
                print(f"Created product: {p['name']} (opening: {qty})")
            else:
                print(f"Product already exists: {p['name']}")

        for s in SAMPLE_SHOPS:
            res = await session.execute(
                select(Shop).where(Shop.name == s["name"], Shop.city == s["city"])
            )
            shop_obj = res.scalar_one_or_none()
            if not shop_obj:
                shop_obj = Shop(
                    name=s["name"],
                    city=s["city"],
                    phone=s["phone"],
                    is_active=True,
                )
                session.add(shop_obj)
                print(f"Created shop: {s['name']} ({s['city']})")
            else:
                print(f"Shop already exists: {s['name']}")

        await session.commit()
        print("Initial data seed completed successfully!")


if __name__ == "__main__":
    asyncio.run(seed())