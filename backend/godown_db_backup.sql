--
-- PostgreSQL database dump
--

\restrict 14ds11YeyEKDpymXFeyBlN14kFw2aDhAmSOVquekVXUVlSkAql2R3nL6N6WIKlo

-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

ALTER TABLE IF EXISTS ONLY public.serial_numbers DROP CONSTRAINT IF EXISTS serial_numbers_product_id_fkey;
ALTER TABLE IF EXISTS ONLY public.serial_numbers DROP CONSTRAINT IF EXISTS serial_numbers_last_shop_id_fkey;
ALTER TABLE IF EXISTS ONLY public.serial_history DROP CONSTRAINT IF EXISTS serial_history_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.serial_history DROP CONSTRAINT IF EXISTS serial_history_shop_id_fkey;
ALTER TABLE IF EXISTS ONLY public.serial_history DROP CONSTRAINT IF EXISTS serial_history_serial_number_id_fkey;
ALTER TABLE IF EXISTS ONLY public.serial_history DROP CONSTRAINT IF EXISTS serial_history_return_id_fkey;
ALTER TABLE IF EXISTS ONLY public.serial_history DROP CONSTRAINT IF EXISTS serial_history_outward_batch_id_fkey;
ALTER TABLE IF EXISTS ONLY public.serial_history DROP CONSTRAINT IF EXISTS serial_history_inward_batch_id_fkey;
ALTER TABLE IF EXISTS ONLY public.serial_history DROP CONSTRAINT IF EXISTS serial_history_device_id_fkey;
ALTER TABLE IF EXISTS ONLY public.returns DROP CONSTRAINT IF EXISTS returns_shop_id_fkey;
ALTER TABLE IF EXISTS ONLY public.returns DROP CONSTRAINT IF EXISTS returns_serial_number_id_fkey;
ALTER TABLE IF EXISTS ONLY public.returns DROP CONSTRAINT IF EXISTS returns_received_by_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.returns DROP CONSTRAINT IF EXISTS returns_product_id_fkey;
ALTER TABLE IF EXISTS ONLY public.returns DROP CONSTRAINT IF EXISTS returns_outward_line_id_fkey;
ALTER TABLE IF EXISTS ONLY public.returns DROP CONSTRAINT IF EXISTS returns_inspected_by_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.returns DROP CONSTRAINT IF EXISTS returns_device_id_fkey;
ALTER TABLE IF EXISTS ONLY public.products DROP CONSTRAINT IF EXISTS products_category_id_fkey;
ALTER TABLE IF EXISTS ONLY public.outward_lines DROP CONSTRAINT IF EXISTS outward_lines_shop_id_fkey;
ALTER TABLE IF EXISTS ONLY public.outward_lines DROP CONSTRAINT IF EXISTS outward_lines_serial_number_id_fkey;
ALTER TABLE IF EXISTS ONLY public.outward_lines DROP CONSTRAINT IF EXISTS outward_lines_product_id_fkey;
ALTER TABLE IF EXISTS ONLY public.outward_lines DROP CONSTRAINT IF EXISTS outward_lines_batch_id_fkey;
ALTER TABLE IF EXISTS ONLY public.outward_batches DROP CONSTRAINT IF EXISTS outward_batches_shop_id_fkey;
ALTER TABLE IF EXISTS ONLY public.outward_batches DROP CONSTRAINT IF EXISTS outward_batches_product_id_fkey;
ALTER TABLE IF EXISTS ONLY public.outward_batches DROP CONSTRAINT IF EXISTS outward_batches_dispatched_by_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.outward_batches DROP CONSTRAINT IF EXISTS outward_batches_device_id_fkey;
ALTER TABLE IF EXISTS ONLY public.inward_lines DROP CONSTRAINT IF EXISTS inward_lines_serial_number_id_fkey;
ALTER TABLE IF EXISTS ONLY public.inward_lines DROP CONSTRAINT IF EXISTS inward_lines_batch_id_fkey;
ALTER TABLE IF EXISTS ONLY public.inward_batches DROP CONSTRAINT IF EXISTS inward_batches_received_by_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.inward_batches DROP CONSTRAINT IF EXISTS inward_batches_product_id_fkey;
ALTER TABLE IF EXISTS ONLY public.inward_batches DROP CONSTRAINT IF EXISTS inward_batches_device_id_fkey;
ALTER TABLE IF EXISTS ONLY public.devices DROP CONSTRAINT IF EXISTS devices_approved_by_id_fkey;
ALTER TABLE IF EXISTS ONLY public.audit_log DROP CONSTRAINT IF EXISTS audit_log_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.audit_log DROP CONSTRAINT IF EXISTS audit_log_device_id_fkey;
DROP INDEX IF EXISTS public.ix_users_username;
DROP INDEX IF EXISTS public.ix_serial_numbers_status;
DROP INDEX IF EXISTS public.ix_serial_numbers_serial_number;
DROP INDEX IF EXISTS public.ix_serial_numbers_product_id;
DROP INDEX IF EXISTS public.ix_serial_numbers_last_shop_id;
DROP INDEX IF EXISTS public.ix_serial_history_user_id;
DROP INDEX IF EXISTS public.ix_serial_history_serial_text;
DROP INDEX IF EXISTS public.ix_serial_history_serial_number_id;
DROP INDEX IF EXISTS public.ix_serial_history_created_at;
DROP INDEX IF EXISTS public.ix_serial_history_action;
DROP INDEX IF EXISTS public.ix_returns_shop_id;
DROP INDEX IF EXISTS public.ix_returns_serial_text;
DROP INDEX IF EXISTS public.ix_returns_serial_number_id;
DROP INDEX IF EXISTS public.ix_returns_return_date;
DROP INDEX IF EXISTS public.ix_products_sku;
DROP INDEX IF EXISTS public.ix_products_category_id;
DROP INDEX IF EXISTS public.ix_outward_lines_transaction_date;
DROP INDEX IF EXISTS public.ix_outward_lines_shop_id;
DROP INDEX IF EXISTS public.ix_outward_lines_serial_text;
DROP INDEX IF EXISTS public.ix_outward_lines_serial_number_id;
DROP INDEX IF EXISTS public.ix_outward_lines_is_matched;
DROP INDEX IF EXISTS public.ix_outward_lines_is_flagged;
DROP INDEX IF EXISTS public.ix_outward_lines_batch_id;
DROP INDEX IF EXISTS public.ix_outward_batches_transaction_date;
DROP INDEX IF EXISTS public.ix_outward_batches_shop_id;
DROP INDEX IF EXISTS public.ix_outward_batches_product_id;
DROP INDEX IF EXISTS public.ix_outward_batches_bill_number;
DROP INDEX IF EXISTS public.ix_inward_lines_serial_number_id;
DROP INDEX IF EXISTS public.ix_inward_lines_batch_id;
DROP INDEX IF EXISTS public.ix_inward_batches_transaction_date;
DROP INDEX IF EXISTS public.ix_inward_batches_product_id;
DROP INDEX IF EXISTS public.ix_devices_device_uid;
DROP INDEX IF EXISTS public.ix_categories_name;
DROP INDEX IF EXISTS public.ix_audit_log_user_id;
DROP INDEX IF EXISTS public.ix_audit_log_entity_type;
DROP INDEX IF EXISTS public.ix_audit_log_entity_id;
DROP INDEX IF EXISTS public.ix_audit_log_created_at;
DROP INDEX IF EXISTS public.ix_audit_log_action;
ALTER TABLE IF EXISTS ONLY public.users DROP CONSTRAINT IF EXISTS users_pkey;
ALTER TABLE IF EXISTS ONLY public.outward_lines DROP CONSTRAINT IF EXISTS uq_outward_lines_batch_serial;
ALTER TABLE IF EXISTS ONLY public.inward_lines DROP CONSTRAINT IF EXISTS uq_inward_lines_batch_serial;
ALTER TABLE IF EXISTS ONLY public.shops DROP CONSTRAINT IF EXISTS shops_pkey;
ALTER TABLE IF EXISTS ONLY public.serial_numbers DROP CONSTRAINT IF EXISTS serial_numbers_pkey;
ALTER TABLE IF EXISTS ONLY public.serial_history DROP CONSTRAINT IF EXISTS serial_history_pkey;
ALTER TABLE IF EXISTS ONLY public.returns DROP CONSTRAINT IF EXISTS returns_pkey;
ALTER TABLE IF EXISTS ONLY public.products DROP CONSTRAINT IF EXISTS products_pkey;
ALTER TABLE IF EXISTS ONLY public.outward_lines DROP CONSTRAINT IF EXISTS outward_lines_pkey;
ALTER TABLE IF EXISTS ONLY public.outward_batches DROP CONSTRAINT IF EXISTS outward_batches_pkey;
ALTER TABLE IF EXISTS ONLY public.inward_lines DROP CONSTRAINT IF EXISTS inward_lines_pkey;
ALTER TABLE IF EXISTS ONLY public.inward_batches DROP CONSTRAINT IF EXISTS inward_batches_pkey;
ALTER TABLE IF EXISTS ONLY public.devices DROP CONSTRAINT IF EXISTS devices_pkey;
ALTER TABLE IF EXISTS ONLY public.categories DROP CONSTRAINT IF EXISTS categories_pkey;
ALTER TABLE IF EXISTS ONLY public.audit_log DROP CONSTRAINT IF EXISTS audit_log_pkey;
ALTER TABLE IF EXISTS ONLY public.alembic_version DROP CONSTRAINT IF EXISTS alembic_version_pkc;
DROP TABLE IF EXISTS public.users;
DROP TABLE IF EXISTS public.shops;
DROP TABLE IF EXISTS public.serial_numbers;
DROP TABLE IF EXISTS public.serial_history;
DROP TABLE IF EXISTS public.returns;
DROP TABLE IF EXISTS public.products;
DROP TABLE IF EXISTS public.outward_lines;
DROP TABLE IF EXISTS public.outward_batches;
DROP TABLE IF EXISTS public.inward_lines;
DROP TABLE IF EXISTS public.inward_batches;
DROP TABLE IF EXISTS public.devices;
DROP TABLE IF EXISTS public.categories;
DROP TABLE IF EXISTS public.audit_log;
DROP TABLE IF EXISTS public.alembic_version;
DROP TYPE IF EXISTS public.user_role;
DROP TYPE IF EXISTS public.serial_status;
DROP TYPE IF EXISTS public.inspection_result;
DROP TYPE IF EXISTS public.history_action;
--
-- Name: history_action; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.history_action AS ENUM (
    'inward_recorded',
    'dispatched_matched',
    'dispatched_unmatched',
    'dispatched_flagged',
    'returned',
    'status_changed',
    'inspected'
);


--
-- Name: inspection_result; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.inspection_result AS ENUM (
    'available',
    'damaged'
);


--
-- Name: serial_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.serial_status AS ENUM (
    'available',
    'dispatched',
    'damaged',
    'lost',
    'under_repair',
    'returned'
);


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role AS ENUM (
    'admin',
    'staff'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: alembic_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alembic_version (
    version_num character varying(32) NOT NULL
);


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id uuid NOT NULL,
    user_id uuid,
    device_id uuid,
    action character varying(100) NOT NULL,
    entity_type character varying(50) NOT NULL,
    entity_id character varying(100),
    details jsonb,
    ip_address character varying(45),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id uuid NOT NULL,
    name character varying(100) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    has_dual_serial boolean DEFAULT false NOT NULL
);


--
-- Name: devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.devices (
    id uuid NOT NULL,
    device_uid character varying(255) NOT NULL,
    label character varying(255),
    approved_by_id uuid,
    approved_at timestamp with time zone,
    is_active boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: inward_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inward_batches (
    id uuid NOT NULL,
    product_id uuid NOT NULL,
    invoice_reference character varying(100),
    transaction_date date NOT NULL,
    received_by_user_id uuid NOT NULL,
    device_id uuid,
    quantity integer NOT NULL,
    remarks text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    inward_type character varying(50) DEFAULT 'stock_in'::character varying NOT NULL
);


--
-- Name: inward_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inward_lines (
    id uuid NOT NULL,
    batch_id uuid NOT NULL,
    serial_number_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: outward_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outward_batches (
    id uuid NOT NULL,
    product_id uuid NOT NULL,
    shop_id uuid NOT NULL,
    delivery_reference character varying(100),
    transaction_date date NOT NULL,
    dispatched_by_user_id uuid NOT NULL,
    device_id uuid,
    quantity integer NOT NULL,
    matched_count integer DEFAULT 0 NOT NULL,
    unmatched_count integer DEFAULT 0 NOT NULL,
    flagged_count integer DEFAULT 0 NOT NULL,
    remarks text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    bill_number character varying(100)
);


--
-- Name: outward_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outward_lines (
    id uuid NOT NULL,
    batch_id uuid NOT NULL,
    serial_text character varying(100) NOT NULL,
    serial_number_id uuid,
    product_id uuid NOT NULL,
    shop_id uuid NOT NULL,
    transaction_date date NOT NULL,
    is_matched boolean DEFAULT false NOT NULL,
    is_flagged_for_review boolean DEFAULT false NOT NULL,
    flag_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    unit_type character varying(20)
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    sku character varying(100),
    category_id uuid NOT NULL,
    brand character varying(100) NOT NULL,
    model character varying(255) NOT NULL,
    size_capacity character varying(100),
    unit character varying(50) DEFAULT 'piece'::character varying NOT NULL,
    serial_number_required boolean DEFAULT true NOT NULL,
    description text,
    opening_stock_qty integer DEFAULT 0 NOT NULL,
    current_stock_qty integer DEFAULT 0 NOT NULL,
    has_had_inward boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: returns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.returns (
    id uuid NOT NULL,
    serial_text character varying(100) NOT NULL,
    serial_number_id uuid,
    outward_line_id uuid,
    shop_id uuid NOT NULL,
    product_id uuid NOT NULL,
    return_date date NOT NULL,
    reason text NOT NULL,
    condition character varying(100),
    received_by_user_id uuid NOT NULL,
    device_id uuid,
    inspection_result public.inspection_result,
    inspected_at timestamp with time zone,
    inspected_by_user_id uuid,
    remarks text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: serial_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.serial_history (
    id uuid NOT NULL,
    serial_number_id uuid,
    serial_text character varying(100) NOT NULL,
    action public.history_action NOT NULL,
    from_status public.serial_status,
    to_status public.serial_status,
    shop_id uuid,
    inward_batch_id uuid,
    outward_batch_id uuid,
    return_id uuid,
    is_matched boolean,
    user_id uuid NOT NULL,
    device_id uuid,
    remarks text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: serial_numbers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.serial_numbers (
    id uuid NOT NULL,
    serial_number character varying(100) NOT NULL,
    product_id uuid NOT NULL,
    status public.serial_status DEFAULT 'available'::public.serial_status NOT NULL,
    last_shop_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    unit_type character varying(20)
);


--
-- Name: shops; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shops (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    city character varying(100),
    phone character varying(30),
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    username character varying(100) NOT NULL,
    full_name character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    role public.user_role NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Data for Name: alembic_version; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.alembic_version (version_num) FROM stdin;
0004
\.


--
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) FROM stdin;
82b803ac-d0e3-4dde-b2c0-003f5d065e4f	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	EXCEL_SHOPS_IMPORTED	shop	bulk	{"column_used": "Particulars", "created_count": 132, "created_shops": ["Akam Home Appliances&Mobiles(CR)", "Amal Cool Air Conditioners(CR)", "ASCO ENGINEERSCR(CR)", "ASSOCIATED COMPUTERS AND SECURITY SOLUTIONS (CR)", "B S AGENCY(CR)", "DIGITAL MART (CR)", "EVERCOOL REFRIGERATION &AIR CONDITION(CR)", "EXCEL APPLIANCES AND AIR CONDITIONS (CR)", "FRIDGE HOUSE(CR)", "Friends Computers Home Appliances(CR)", "G CONNECT(CR)", "HOME CHOICE WANDOOR(CR)", "INFRA DIGITAL MART FACTORY OUTLET(CR)", "KALYANI E MART(CR)", "KMK Electronics & Home Appliances( CR)", "MARVEL APPIANCES (CR)", "NEW WAY CENTER (CR)", "PRAKASH TRADERS", "SHAJAHAN TV& FRIDGE HOUSE (CR)", "SIGMA ELECTRONICS & HOME BAZAR NLMBR(CR)", "STANTECH TRADING LLP(CR)", "SUPREME KOTTAKKAL (CR)", "TECHNO COOL(CR)", "TOP FURNITURE AND HOME APPLIANCES(CR)", "AIWA COLLECTION & DISTRIBUTIONS", "Akam Home Appliances & Mobiles", "Associated Computers and Security Solutions (Fmty)", "AYISHA KUTTY", "B & M 2 INTERNATIONAL INVESTMENT GROUP", "Choice Home Selection (Chapanangadi)", "CITY CHOICE CMD (F)", "CLASSICO HOME CENTRE(EDPL)", "Classico Home Centre (Vlry)", "Cool Land Tirur", "COOL MART HOME APPLIANCES (NEW)", "Digital Mart", "DIGITAL MART (AKD)", "Digital Mart (Kvnr)", "Dream Digital", "Eminent Electricals", "E WORLD Home Appliances(New)", "Friends Computers Home Appliances", "GK ENTERPRISES", "Glockery Home Centre", "Home Land Home Needs", "HOMEZO FURNITURE AND HOME APPLIANCES (FMTY)", "Infra Digital Mart Factory Out Let", "KATTIL HOME APPLIANCE(Pmbipdk)", "KATTIPARUTHY HOME GUIDE", "Kk Moidheen & Son"]}	\N	2026-10-08 12:51:00.963244+05:30
1fc17411-dd15-4160-a2c5-64542b90139a	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	DEVICE_APPROVED	device	14a77e6e-6251-4bf8-b839-519260e205ae	{"label": "Android Godown Scanner", "device_uid": "0300630b-cb12-4010-af1e-1c414df029f1"}	\N	2026-10-08 13:14:39.154519+05:30
559e2926-542c-4218-9297-3c204177b056	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	USER_UPDATED	user	433ebcc8-1377-4432-a88a-9b155a534784	{"role": "staff", "username": "shihab", "is_active": true}	\N	2026-10-08 13:15:02.517058+05:30
277bb834-ac60-470b-8099-c79e580ed0f2	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	EXCEL_SHOPS_IMPORTED	shop	bulk	{"column_used": "Particulars", "created_count": 188, "created_shops": ["ANAS HOME APPLIANCES", "DR.DOOR", "EVERCOOL ENTERPRISES", "FRIENDS COMPUTERS HOME APPLAINCES & SECURITY SYSTEM", "GODS OWN", "GRAND HOME APPLIANCE", "HELAN DIGITAL MART", "KADOOR ELECTRONICS", "KALPAKA ELECTRONICS & HOME BAZAR", "Kannankandy Fridge centre", "KASIM KUMMALI ADV", "MAB TECH EQUIPMENT PRIVATE LIMITED(New)", "Mandhi Palce", "MANSOOR PATTAMBI", "Mr YESHUDAS", "MUJEEB ARIMBRA", "NESTO HYPER MARKET (CLT)", "NEW WHITE HOME", "OMEGA AGENCIES", "PV STORE", "PV STORE EKKAPPARAMBU", "REAL AGENCY", "RETAIL BILL", "RIYAS ROK", "SHAMEER PANDI", "SIGMA ELECTRONICS MANJERI", "SMART HOME APPLIANCES", "S.P TRADERS", "VAVA FURNITURE AND HOME APPLIANCES(New)", "VK GROUP", "AKAM  HOME APPLIANCES & MOBILES", "A K M STORE", "ASHIKH ELECTRONIC AND HOME APPLIANCES", "Brand House Agencies", "BROTHERS HOME APPLAINES & FURNITURE", "BUDGET FURNITURE & HOME APPLIANCES", "BUDGET FURNITURE & HOME APPLIANCES (PNKD)", "CHOICE HOME SERVICES (Mtvlr)", "Cool India Home Needs & Appliances", "Cool Makers", "ELECTRO WORLD FRIDGE HOUSE", "ELITE METALS & HOME NEEDS  MJRY", "E MAX DIGITAL", "FAMILY HOMELAND ELECTRICALS & SANITARY", "FAMILY METALS & FURNITURE", "FOCUS FURNITURE & ELECTRONICS", "FRIDGE HOUSE", "HAPPY HOME", "Happy Home Hardware & Electricals", "HI MART HYPERMARKET"]}	\N	2026-10-08 15:53:10.20424+05:30
11d8bbfa-cbef-4387-8a1d-f672b03fdc02	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	SHOP_PERMANENTLY_DELETED	shop	2719f84c-c499-4704-b8f5-f3f687d0dc88	{"city": null, "name": "A K M STORE"}	\N	2026-10-08 15:53:24.982194+05:30
5511b4a2-7179-4190-b870-d1ed627d9dbf	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	SHOP_PERMANENTLY_DELETED	shop	c5858f44-0ef4-4ce0-8db3-7a3f94ed3b41	{"city": null, "name": "ABCD ELECTRONICS & HOME APPLIANCES"}	\N	2026-10-08 15:53:34.981684+05:30
ac80f7c2-fb72-4782-a076-bf19aac90cd2	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	EXCEL_SHOPS_IMPORTED	shop	bulk	{"column_used": "Particulars", "created_count": 228, "created_shops": ["ANAS HOME APPLIANCES", "BENZY HOSPITALS PRIVATE LIMITED", "DR.DOOR", "EVERCOOL ENTERPRISES", "FRIENDS COMPUTERS HOME APPLAINCES & SECURITY SYSTEM", "GODS OWN", "GRAND HOME APPLIANCE", "HAYATH MEDICAL CENTRE", "HELAN DIGITAL MART", "KADOOR ELECTRONICS", "KALPAKA ELECTRONICS (FRK)", "KALPAKA ELECTRONICS & HOME BAZAR", "Kalpaka Electronics & Home Bazar Mlp", "Kannankandy Fridge centre", "KASIM KUMMALI ADV", "KERALA FLIGHT ACADEMY PRIVATE LIMITED", "MAB TECH EQUIPMENT PRIVATE LIMITED(New)", "Mandhi Palce", "MANSOOR PATTAMBI", "MERRY SOUL ENTERPRISE", "Mr YESHUDAS", "MUJEEB ARIMBRA", "NESTO HYPER MARKET (CLT)", "NEW TECH COOLING SOLUTIONS", "NEW WHITE HOME", "OMEGA AGENCIES", "PRAKASH TRADERS", "PV STORE", "PV STORE EKKAPPARAMBU", "REAL AGENCY", "RETAIL BILL", "RIYAS ROK", "SHAMEER PANDI", "SIGMA ELECTRONICS MANJERI", "SMART HOME APPLIANCES", "S.P TRADERS", "VAVA FURNITURE AND HOME APPLIANCES(New)", "VK GROUP", "AKAM  HOME APPLIANCES & MOBILES", "A K M STORE", "ASHIKH ELECTRONIC AND HOME APPLIANCES", "Brand House Agencies", "BROTHERS HOME APPLAINES & FURNITURE", "BUDGET FURNITURE & HOME APPLIANCES", "BUDGET FURNITURE & HOME APPLIANCES (PNKD)", "CHOICE HOME SERVICES (Mtvlr)", "Cool India Home Needs & Appliances", "Cool Makers", "DIGITAL MART", "Digital Mart (Kvnr)"]}	\N	2026-10-08 15:56:28.770661+05:30
3d8c0965-bdc3-463d-85ce-1d8b05acff39	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	EXCEL_SHOPS_IMPORTED	shop	bulk	{"column_used": "Particulars", "created_count": 92, "created_shops": ["Akam Home Appliances&Mobiles(CR)", "Amal Cool Air Conditioners(CR)", "ASCO ENGINEERSCR(CR)", "ASSOCIATED COMPUTERS AND SECURITY SOLUTIONS (CR)", "B S AGENCY(CR)", "DIGITAL MART (CR)", "EVERCOOL REFRIGERATION &AIR CONDITION(CR)", "EXCEL APPLIANCES AND AIR CONDITIONS (CR)", "FRIDGE HOUSE(CR)", "Friends Computers Home Appliances(CR)", "G CONNECT(CR)", "HOME CHOICE WANDOOR(CR)", "INFRA DIGITAL MART FACTORY OUTLET(CR)", "KALYANI E MART(CR)", "KMK Electronics & Home Appliances( CR)", "MARVEL APPIANCES (CR)", "NEW WAY CENTER (CR)", "SHAJAHAN TV& FRIDGE HOUSE (CR)", "SIGMA ELECTRONICS & HOME BAZAR NLMBR(CR)", "STANTECH TRADING LLP(CR)", "SUPREME KOTTAKKAL (CR)", "TECHNO COOL(CR)", "TOP FURNITURE AND HOME APPLIANCES(CR)", "Akam Home Appliances & Mobiles", "Associated Computers and Security Solutions (Fmty)", "AYISHA KUTTY", "B & M 2 INTERNATIONAL INVESTMENT GROUP", "Choice Home Selection (Chapanangadi)", "CITY CHOICE CMD (F)", "CLASSICO HOME CENTRE(EDPL)", "Cool Land Tirur", "COOL MART HOME APPLIANCES (NEW)", "DIGITAL MART (AKD)", "Friends Computers Home Appliances", "Glockery Home Centre", "Home Land Home Needs", "HOMEZO FURNITURE AND HOME APPLIANCES (FMTY)", "KATTIL HOME APPLIANCE(Pmbipdk)", "Kk Moidheen & Son", "KMK Electronics & Home Appliances", "KRIPA HOME APPLIACES", "Sana Home Bazar(Puthanathani)", "Shajahan TV & Fridge House", "THAYYIL HOME CENTER", "Vee Key Home Appliaces", "AERONEX COOLING SOLUTION(New)", "ASSOCIATED ELECTRONICS", "Benzy Home Makers Pvt Ltd", "BigBuy Airconditioning Engineers", "BigBuy Airconditioning Engineers (Vngara)"]}	\N	2026-10-08 15:56:49.875827+05:30
9418b640-e805-4a73-8e57-efdd368c710d	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	CATEGORY_CREATED	category	a61627a9-d0a7-49b8-af5f-56c872026561	{"name": "AC", "has_dual_serial": true}	\N	2026-10-08 16:00:02.724115+05:30
ea82716c-d442-4114-90a9-a0597240fcdf	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	CATEGORY_CREATED	category	c0f349e1-9209-422e-b304-a5f3d0bbf5b8	{"name": "WASHING MACHINE", "has_dual_serial": false}	\N	2026-10-08 16:02:46.527857+05:30
be88e31b-d064-491a-9d80-c81b4e039dd2	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	CATEGORY_CREATED	category	3866bb27-b9b4-40c1-99b8-2aed06198a18	{"name": "REFERIGERATOR", "has_dual_serial": false}	\N	2026-10-08 16:03:02.90933+05:30
ddd2837f-54a3-483b-bf74-5ce455e002e6	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	CATEGORY_CREATED	category	043d664f-f89e-4187-99f0-ff9bceb2575c	{"name": "TV", "has_dual_serial": false}	\N	2026-10-08 16:03:49.907974+05:30
b855a7b0-dc44-4308-9ab5-84f2d896c58d	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	DEVICE_APPROVED	device	e5621cd5-aaa0-40f3-9e5f-6c02b89d0d0a	{"label": "Android Godown Scanner", "device_uid": "16b82feb-9760-4ded-a520-6d92be809377"}	\N	2026-10-08 16:39:58.394775+05:30
38fabcd9-a46b-4d88-b9c8-e399ad292a2d	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	b3c1b461-b0f1-4c8e-9dbe-8dd56d2e6a95	{"name": "ROCKWELL GFR 450 DDUC-5S", "brand": "ROCKWELL", "model": "GFR 450 DDUC-5S", "opening_stock_qty": 0}	\N	2026-10-08 16:59:51.604125+05:30
ba9bc558-78d3-4aa3-9b35-227771c0b5d8	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	79506c87-6018-4ea5-9b28-6462f32ade86	{"name": "ROCKWELL GFR 550 DDUCSS5S", "brand": "ROCKWELL", "model": "GFR 550 DDUCSS5S", "opening_stock_qty": 0}	\N	2026-10-08 17:00:55.19106+05:30
efe772ac-e2b7-4a1e-af87-d5a03338f84c	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	0cc42ac9-3e11-4609-9075-fbc5e90bf39c	{"name": "ROCKWELL GFR 910 UC5S", "brand": "ROCKWELL", "model": "GFR 910 UC5S", "opening_stock_qty": 0}	\N	2026-10-08 17:01:52.374719+05:30
36c673eb-eaae-4a51-8fba-a7c38cce1c97	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	CATEGORY_CREATED	category	5d3395d9-808e-4fff-815c-a0facdf8bbdb	{"name": "FREEZER", "has_dual_serial": false}	\N	2026-10-08 16:58:41.867432+05:30
b3c4b7af-ee12-42d0-840b-0eef0cba1646	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_OPENING_STOCK_EDITED	product	7f4ac78e-a27b-428d-8d41-09e90e30beb2	{"diff": 2, "name": "ROCKWELL GFR1210F", "has_had_inward": false, "new_current_stock": 2, "new_opening_stock": 2, "old_current_stock": 0, "old_opening_stock": 0}	\N	2026-10-08 16:59:10.530479+05:30
8dbe0d27-56c1-46ee-afb1-f9a213623359	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_UPDATED	product	7f4ac78e-a27b-428d-8d41-09e90e30beb2	{"name": "ROCKWELL GFR1210F", "is_active": true}	\N	2026-10-08 16:59:10.530479+05:30
0d471562-94cf-49f8-b7b7-a436c7985106	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	7f4ac78e-a27b-428d-8d41-09e90e30beb2	{"name": "ROCKWELL GFR1210F", "brand": "ROCKWELL", "model": "GFR1210F", "opening_stock_qty": 0}	\N	2026-10-08 16:59:02.587912+05:30
e4e9449a-cf7e-422e-813d-f48ba5918344	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_OPENING_STOCK_EDITED	product	7f4ac78e-a27b-428d-8d41-09e90e30beb2	{"diff": -2, "name": "ROCKWELL GFR1210F", "has_had_inward": false, "new_current_stock": 0, "new_opening_stock": 0, "old_current_stock": 2, "old_opening_stock": 2}	\N	2026-10-08 16:59:17.376888+05:30
f04f56f8-7818-479a-a132-d9d5e275ad6d	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_UPDATED	product	7f4ac78e-a27b-428d-8d41-09e90e30beb2	{"name": "ROCKWELL GFR1210F", "is_active": true}	\N	2026-10-08 16:59:17.376888+05:30
8d07dc94-2199-4918-9c3d-53ff07ae2590	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	434b9a12-b1bf-4628-92eb-d8c334d06686	{"name": "ROCKWELL GFR 550 DDUC5S", "brand": "ROCKWELL", "model": "GFR 550 DDUC5S", "opening_stock_qty": 0}	\N	2026-10-08 17:00:26.890128+05:30
712c8015-9609-4106-bf7e-b868767e2301	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	0fd5dc56-f051-441c-a32f-031aa85c4438	{"name": "ROCKWELL GFR 910 UC5S", "brand": "ROCKWELL", "model": "GFR 910 UC5S", "opening_stock_qty": 0}	\N	2026-10-08 17:01:12.983859+05:30
5ba34572-3759-487a-b539-3581f8cd0a4e	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	4f7e752a-a900-4279-a7f3-bdd59c7e4887	{"name": "ROCKWELL ROCKWELL MB-100", "brand": "ROCKWELL", "model": "ROCKWELL MB-100", "opening_stock_qty": 0}	\N	2026-10-08 17:02:27.009787+05:30
1a1acd84-ce02-4e41-9aff-554a97f0865c	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	67a2e9f1-233d-4ea7-a576-5fc33861d833	{"name": "ROCKWELL RVC 1100", "brand": "ROCKWELL", "model": "RVC 1100", "opening_stock_qty": 0}	\N	2026-10-08 17:02:45.326261+05:30
146f1378-83fc-4585-88af-45c76fdf172a	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	acb37210-eb8a-4759-b4f0-fb46e2a90e7a	{"name": "ROCKWELL RVC 400", "brand": "ROCKWELL", "model": "RVC 400", "opening_stock_qty": 0}	\N	2026-10-08 17:03:13.350828+05:30
5a0b08a7-8e4a-464a-aa3d-45eacb0cd763	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	72aa311b-e0c8-4a6f-8d9e-80c9c5cad30f	{"name": "ROCKWELL RVC 550", "brand": "ROCKWELL", "model": "RVC 550", "opening_stock_qty": 0}	\N	2026-10-08 17:03:59.677214+05:30
2cdfa137-b69d-4717-b19b-de1de34e7f0c	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	8d2b048f-fb53-476e-82e4-caba8d509b76	{"name": "ROCKWELL RVC 700", "brand": "ROCKWELL", "model": "RVC 700", "opening_stock_qty": 0}	\N	2026-10-08 17:04:13.25429+05:30
09cf18ea-f8f0-4ce2-b745-5dfd2c8168b7	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	2a6fb377-44d5-4b58-9882-6a4e69839104	{"name": "ROCKWELL SFR 250 SDU-4S", "brand": "ROCKWELL", "model": "SFR 250 SDU-4S", "opening_stock_qty": 0}	\N	2026-10-08 17:04:40.124677+05:30
82ddb739-5a02-42ff-9fdb-fdd988b17f3b	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	e005dfbd-c056-416f-8fb9-74067e0a4659	{"name": "ROCKWELL SFR 350 DDU5S", "brand": "ROCKWELL", "model": "SFR 350 DDU5S", "opening_stock_qty": 0}	\N	2026-10-08 17:05:34.143567+05:30
63081695-25f8-45f2-9593-aab59941ccc6	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	98c6d742-2bce-4e95-9ba6-daa72bebd5f0	{"name": "ROCKWELL SFR 350GTS LED", "brand": "ROCKWELL", "model": "SFR 350GTS LED", "opening_stock_qty": 0}	\N	2026-10-08 17:06:10.005308+05:30
4b9e2d22-3ac4-4a45-bff4-71e7f9edce41	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	7449ebcc-8d69-42c3-8df2-d20a0c37a96c	{"name": "ROCKWELL SFR 450 DDU-5S", "brand": "ROCKWELL", "model": "SFR 450 DDU-5S", "opening_stock_qty": 0}	\N	2026-10-08 17:06:24.958425+05:30
e9d04f37-b6a5-4939-986a-e045f2193f7d	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	26eca82c-bd82-4819-a3c9-cab776834bfb	{"name": "ROCKWELL SFR 450 GTS LED", "brand": "ROCKWELL", "model": "SFR 450 GTS LED", "opening_stock_qty": 0}	\N	2026-10-08 17:06:49.050572+05:30
9ed82d75-8d9d-40fb-833e-4795a9a3f662	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	5dfb33bf-2c0a-40c2-a340-448ad9c825d5	{"name": "ROCKWELL SFR 550 DDU5S", "brand": "ROCKWELL", "model": "SFR 550 DDU5S", "opening_stock_qty": 0}	\N	2026-10-08 17:07:04.86483+05:30
87ed4f38-a041-4d3a-b10f-6dddbc7e1c1c	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	bacc9a8e-8ce2-455f-9166-809aba107dfa	{"name": "ROCKWELL SFR 750 TDU5S", "brand": "ROCKWELL", "model": "SFR 750 TDU5S", "opening_stock_qty": 0}	\N	2026-10-08 17:08:46.137962+05:30
31c70046-f9c2-413e-ba14-8d0fda87a16a	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_DEACTIVATED	product	0fd5dc56-f051-441c-a32f-031aa85c4438	{"name": "ROCKWELL GFR 910 UC5S"}	\N	2026-10-08 17:12:18.722915+05:30
fcf17444-83a0-467c-8423-5e8135a3cb48	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	b98ff282-df28-4a8b-962f-0da93398777c	{"name": "GENERAL 12CGWA-B 1.0T INV AC", "brand": "GENERAL", "model": "12CGWA-B 1.0T INV AC", "opening_stock_qty": 0}	\N	2026-10-08 17:13:23.323547+05:30
b0069967-9dc3-4603-8c6f-99ea06c4cb6e	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	3f5872a1-df35-4bf7-85b4-22cc53085f79	{"name": "GENERAL ASGA 18 BMAA-B 1.5T Split Ac", "brand": "GENERAL", "model": "ASGA 18 BMAA-B 1.5T Split Ac", "opening_stock_qty": 0}	\N	2026-10-08 17:13:51.763891+05:30
a9c911df-1f40-48c2-b633-33fdb8d731f2	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	43fd84b0-ee86-4411-9d4c-0a0ac31959af	{"name": "GENERAL ASGA18BUTA-B", "brand": "GENERAL", "model": "ASGA18BUTA-B", "opening_stock_qty": 0}	\N	2026-10-08 17:14:09.64954+05:30
f2934e73-7c76-4353-a067-33790833d994	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	8811c429-0cf7-477f-ada4-18fdaa1beee1	{"name": "GENERAL ASGA18BUTA-B", "brand": "GENERAL", "model": "ASGA18BUTA-B", "opening_stock_qty": 0}	\N	2026-10-08 17:14:29.48848+05:30
936b629b-2408-486e-bb06-287e57bf9c55	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_UPDATED	product	43fd84b0-ee86-4411-9d4c-0a0ac31959af	{"name": "GENERAL ASGA 24 BMAA-B 2.0T Split Ac", "is_active": true}	\N	2026-10-08 17:14:46.283152+05:30
36a99d9d-4fb3-49d4-a080-becfc97ce8e6	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	09582965-46f7-4019-bba0-7161ec1cfeb3	{"name": "GENERAL ASGA24BUTA-B 2T", "brand": "GENERAL", "model": "ASGA24BUTA-B 2T", "opening_stock_qty": 0}	\N	2026-10-08 17:15:02.38574+05:30
742ab445-1399-4738-aeb7-3c83f198ce19	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	03aca04a-fcf1-4708-bbac-074130fc2c0f	{"name": "GENERAL ASGG 12CGAB-B 1T INV AC", "brand": "GENERAL", "model": "ASGG 12CGAB-B 1T INV AC", "opening_stock_qty": 0}	\N	2026-10-08 17:15:32.1243+05:30
5265442b-0a71-4ec7-bd0f-e752e2281121	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	2466d044-b519-4a59-92f5-67a261d23b44	{"name": "GENERAL ASGG 12 CGTB   1 Tn 5*", "brand": "GENERAL", "model": "ASGG 12 CGTB   1 Tn 5*", "opening_stock_qty": 0}	\N	2026-10-08 17:16:00.841635+05:30
f1c3246d-a592-451a-bb50-f71c6105e6d9	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	f306cbd1-f4fb-45e2-b408-ab8cb46e536b	{"name": "GENERAL ASGG12CGWA-B 1 T INV AC 4*", "brand": "GENERAL", "model": "ASGG12CGWA-B 1 T INV AC 4*", "opening_stock_qty": 0}	\N	2026-10-08 17:16:18.57077+05:30
6f894afd-5cd8-4f66-8bc5-46cc55a8d149	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	953f64bb-183a-4dcc-ad51-4a9b8d1ba754	{"name": "GENERAL ASGG 12 CKWA-B 1.OT INV AC 3*", "brand": "GENERAL", "model": "ASGG 12 CKWA-B 1.OT INV AC 3*", "opening_stock_qty": 0}	\N	2026-10-08 17:16:40.348617+05:30
038de2cd-6737-4d4f-82b1-d540eb4674c3	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	06521486-9173-4469-a926-09fdde8f7fba	{"name": "GENERAL ASGG 12 CPWA-B 1T INV AC3*", "brand": "GENERAL", "model": "ASGG 12 CPWA-B 1T INV AC3*", "opening_stock_qty": 0}	\N	2026-10-08 17:17:23.484745+05:30
b75a63db-df8d-47df-a2f8-1dbd1fb46183	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	03316b63-3179-42e1-9210-df9a792649a9	{"name": "GENERAL ASGG 18 CEAC-B 1.5T INC AC 5*", "brand": "GENERAL", "model": "ASGG 18 CEAC-B 1.5T INC AC 5*", "opening_stock_qty": 0}	\N	2026-10-08 17:17:40.86429+05:30
9d72dc8e-2eba-442a-8fdb-3b3dc77dc796	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	a644739a-efcc-47fb-8117-bcfc36c4b41e	{"name": "GENERAL ASGG 18 CETB-B 1.5T INV AC 5*", "brand": "GENERAL", "model": "ASGG 18 CETB-B 1.5T INV AC 5*", "opening_stock_qty": 0}	\N	2026-10-08 17:18:02.716345+05:30
dc2e6d02-a0cd-4d9b-9c57-01ed3fc2fb32	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	0dd497cc-caf0-4134-9437-535b16365a0b	{"name": "FORMENTY FM 32 HDRPT1", "brand": "FORMENTY", "model": "FM 32 HDRPT1", "opening_stock_qty": 0}	\N	2026-10-09 11:29:46.017984+05:30
043c1939-7f27-4dd1-bcac-53e695a9dd7b	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	75b4ac90-2d54-4c52-aaae-1c86b6554ae8	{"name": "FORMENTY FM32HDSPB2YU LED- LUMINOR SERIES", "brand": "FORMENTY", "model": "FM32HDSPB2YU LED- LUMINOR SERIES", "opening_stock_qty": 0}	\N	2026-10-09 11:30:01.806721+05:30
33840c27-25ee-481e-b5c0-67d6f43d5135	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	f1405e84-41dc-4b22-bd87-bd9006a17c81	{"name": "FORMENTY FM 32 HDSPT2 SMART", "brand": "FORMENTY", "model": "FM 32 HDSPT2 SMART", "opening_stock_qty": 0}	\N	2026-10-09 11:30:14.054387+05:30
64aa9f28-e08a-4653-a4ae-9281c5a96b42	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	8590701f-97f0-486e-9b47-ced013bd4c1d	{"name": "FORMENTY FM32HDSQSPR1DX Q LED-SPECTRA SERIES", "brand": "FORMENTY", "model": "FM32HDSQSPR1DX Q LED-SPECTRA SERIES", "opening_stock_qty": 0}	\N	2026-10-09 11:30:41.699172+05:30
8d59d932-9aa8-48c2-a8b1-d4b005467205	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	7999322a-f1bb-4a0f-a72e-475b819b6a3f	{"name": "FORMENTY FM43UHDQSPR4DX QLED-SPECTRA SERIES", "brand": "FORMENTY", "model": "FM43UHDQSPR4DX QLED-SPECTRA SERIES", "opening_stock_qty": 0}	\N	2026-10-09 11:30:57.553489+05:30
d4cfbe51-1a72-4c7a-8b21-2cd4d10c8bee	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	8531cbb7-5457-49c3-9e0d-4529700e42bf	{"name": "FORMENTY FM55UHDQSPR5DX Q LED- SPECTRA SERIES", "brand": "FORMENTY", "model": "FM55UHDQSPR5DX Q LED- SPECTRA SERIES", "opening_stock_qty": 0}	\N	2026-10-09 11:31:11.920615+05:30
7293ad19-9f8a-4fe4-adc6-9c67a7dab70a	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	4958f751-6916-45fc-8725-d0bf223ac9c9	{"name": "FORMENTY LED FMTY FM32HDSQTVDXB1 Google Q Led VELORA", "brand": "FORMENTY", "model": "LED FMTY FM32HDSQTVDXB1 Google Q Led VELORA", "opening_stock_qty": 0}	\N	2026-10-09 11:32:19.460036+05:30
00449b8a-2b77-4e17-ae6c-df3b1a041191	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	730cc975-b1e6-48b6-94dc-8f5686b98c7a	{"name": "FORMENTY LED FMTY -FM32HDSQTVWWCR GOOGLE Q LED TV -Cinara", "brand": "FORMENTY", "model": "LED FMTY -FM32HDSQTVWWCR GOOGLE Q LED TV -Cinara", "opening_stock_qty": 0}	\N	2026-10-09 11:32:31.151671+05:30
291fa597-b9e4-401d-bde2-6e98ea010a85	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	00d31b1c-02fe-454f-ad9c-3bd47c74f7d0	{"name": "FORMENTY LED FMTY FM32HDTVDXB1 GOOGLE  QLED TV VELORA", "brand": "FORMENTY", "model": "LED FMTY FM32HDTVDXB1 GOOGLE  QLED TV VELORA", "opening_stock_qty": 0}	\N	2026-10-09 11:32:54.063222+05:30
40dbd592-446a-407a-bb14-c8159ead3695	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	9ab2a8e4-e693-47f2-9024-c1a791556c8f	{"name": "FORMENTY LED FMTY FM40FDSQTVDXB2 Google Q Led VELORA", "brand": "FORMENTY", "model": "LED FMTY FM40FDSQTVDXB2 Google Q Led VELORA", "opening_stock_qty": 0}	\N	2026-10-09 11:33:14.210849+05:30
c130b88f-46ed-4d07-9089-4ec0112132f8	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	73cfffaa-0a4c-4841-8df0-9a5a9393b343	{"name": "FORMENTY LED FMTY FM43UHDQTVDXB4 4K UHD Q LED VELORA", "brand": "FORMENTY", "model": "LED FMTY FM43UHDQTVDXB4 4K UHD Q LED VELORA", "opening_stock_qty": 0}	\N	2026-10-09 11:33:47.619372+05:30
f8e318bf-f0ea-465d-a7db-6a0966432b30	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	4c32c360-3147-44e1-b8f6-4ade7ab898b1	{"name": "FORMENTY LED FMTY -FM55UHDQTVDXB5 GOOGLE Q LED TV VELORA", "brand": "FORMENTY", "model": "LED FMTY -FM55UHDQTVDXB5 GOOGLE Q LED TV VELORA", "opening_stock_qty": 0}	\N	2026-10-09 11:34:05.174657+05:30
4c41691d-8e40-487a-aa95-a2da511fbd78	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	7100a1c9-9c26-447b-b802-c50f699ef157	{"name": "GENERAL ASGG 24CEAC-B 2T INV AC 5*", "brand": "GENERAL", "model": "ASGG 24CEAC-B 2T INV AC 5*", "opening_stock_qty": 0}	\N	2026-10-09 17:54:22.402935+05:30
bc8290ec-09eb-4806-83ed-56eacb2efe45	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	94a0f4bd-acc7-40bc-832b-b4e1b4afae85	{"name": "GENERAL ASGG 22CNWA-B 1.8T INV AC 3*", "brand": "GENERAL", "model": "ASGG 22CNWA-B 1.8T INV AC 3*", "opening_stock_qty": 0}	\N	2026-10-09 17:55:29.869288+05:30
08e9899a-b5ae-411a-83c6-e133bb71f4d8	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	15b44915-d3de-434f-b570-e4e605161410	{"name": "GENERAL ASGG 18 CNWA-B 1.5T INV AC 3*", "brand": "GENERAL", "model": "ASGG 18 CNWA-B 1.5T INV AC 3*", "opening_stock_qty": 0}	\N	2026-10-09 17:56:02.364721+05:30
9ca3c427-ea8b-4d06-9168-664324f16b25	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	2f6867f2-d0a6-4f11-91cc-06d9eda1e250	{"name": "GENERAL ASGG 18 CKWA-B 1.5T INV AC 3*", "brand": "GENERAL", "model": "ASGG 18 CKWA-B 1.5T INV AC 3*", "opening_stock_qty": 0}	\N	2026-10-09 17:56:28.124602+05:30
e98c7abf-503c-4a63-9844-efff320fdc91	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	SHOP_PERMANENTLY_DELETED	shop	7fd63368-cfd3-408d-840a-ccc20942bba8	{"city": null, "name": "KMK ELECTRONICS&HOME APPLIANCES"}	\N	2026-10-09 17:40:26.197631+05:30
c6a427db-cd39-4ab9-828a-cb64a0b0237f	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	48f9f792-e076-4970-9506-fd1c589a344c	{"name": "FORMENTY AC FMTY Split Inverter FRIO 1.0T3*-Fm12ininv3froed", "brand": "FORMENTY", "model": "AC FMTY Split Inverter FRIO 1.0T3*-Fm12ininv3froed", "opening_stock_qty": 0}	\N	2026-10-09 17:46:02.662567+05:30
6ff2b2da-4949-4939-9008-9c292272e9f7	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	67303761-7b54-48c5-8f2a-3898a2a33a48	{"name": "CARRIER AC CARRIER 18K INDUS GXI ALPHA HYBRIDJET 1.5 TON 3*", "brand": "CARRIER", "model": "AC CARRIER 18K INDUS GXI ALPHA HYBRIDJET 1.5 TON 3*", "opening_stock_qty": 0}	\N	2026-10-09 17:48:06.262595+05:30
5bbb1deb-a632-4c1c-9e16-c4c9937147b0	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	b837c539-50a3-4150-9fe9-919c841edc00	{"name": "CARRIER AC CARRIER 19K EXCEED LUMO GXI 1.5 T 5*", "brand": "CARRIER", "model": "AC CARRIER 19K EXCEED LUMO GXI 1.5 T 5*", "opening_stock_qty": 0}	\N	2026-10-09 17:48:32.256582+05:30
93ab6756-ecf9-4f26-9d5c-3b92ff31f8b1	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	c470be68-a897-4619-a664-8de8de92bf20	{"name": "CARRIER AC MIDEA 12K SANTIS NXG (V-PRO) DLX INV 1 TON 3*", "brand": "CARRIER", "model": "AC MIDEA 12K SANTIS NXG (V-PRO) DLX INV 1 TON 3*", "opening_stock_qty": 0}	\N	2026-10-09 17:48:52.548906+05:30
e334981a-c6fd-4c8c-b96e-7359d50d8b89	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	a2943f0e-4eac-4199-bec0-b45cdb2e2a96	{"name": "CARRIER CARRIER 24K XCEED EDGE GXIINV AC 5*", "brand": "CARRIER", "model": "CARRIER 24K XCEED EDGE GXIINV AC 5*", "opening_stock_qty": 0}	\N	2026-10-09 17:49:21.769679+05:30
ccd98d22-debb-49a6-b543-04227609d852	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	944814a5-6009-4f50-b13e-131dad62243e	{"name": "CARRIER CARRIER AC 12K XCEL EDGE GXI INV AC 5*", "brand": "CARRIER", "model": "CARRIER AC 12K XCEL EDGE GXI INV AC 5*", "opening_stock_qty": 0}	\N	2026-10-09 17:49:38.784396+05:30
6f26f59c-62cd-4ebd-98eb-9106d56b9aad	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	90492d3d-ac36-4a1f-bc8f-b9005c976939	{"name": "CARRIER CARRIER AC 24K XCEED EDGE GXI ALPHA HYBRIDJET 3*", "brand": "CARRIER", "model": "CARRIER AC 24K XCEED EDGE GXI ALPHA HYBRIDJET 3*", "opening_stock_qty": 0}	\N	2026-10-09 17:49:52.37412+05:30
d797968b-57b1-47e0-a959-d05861a3cb72	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	fa8b239a-c9e1-43d7-bf5d-37c9e0a3d0dc	{"name": "GENERAL ECCGA4 EXTENDED COMPREHNSIVE COVER(F/I/C)4YR", "brand": "GENERAL", "model": "ECCGA4 EXTENDED COMPREHNSIVE COVER(F/I/C)4YR", "opening_stock_qty": 0}	\N	2026-10-09 17:52:48.561338+05:30
2d4d97a3-2499-45d4-b195-70a5c05fb583	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	26d7311e-4fe3-49bf-bd63-037cf843adbf	{"name": "GENERAL ASSGG24CGWA-B 2T INV AC 4*", "brand": "GENERAL", "model": "ASSGG24CGWA-B 2T INV AC 4*", "opening_stock_qty": 0}	\N	2026-10-09 17:53:04.802408+05:30
931fe014-2526-41eb-9261-35c8ea9bbc28	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	ea453d9a-85fb-4293-b1cc-2cabf84cd453	{"name": "GENERAL ASGG30CEAC.B 2.5 T INV AC 5*", "brand": "GENERAL", "model": "ASGG30CEAC.B 2.5 T INV AC 5*", "opening_stock_qty": 0}	\N	2026-10-09 17:53:30.112812+05:30
e8ce2daa-7ab7-4113-995d-f3bb4b0438f9	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	5afc04e5-5ae4-4f5e-8757-24c9942f0e96	{"name": "GENERAL ASGG 24 CPAB-B 3*", "brand": "GENERAL", "model": "ASGG 24 CPAB-B 3*", "opening_stock_qty": 0}	\N	2026-10-09 17:53:47.19933+05:30
3c87c86e-88fa-4fcc-9278-a7e2fda00f59	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_CREATED	product	63bea063-3723-4969-9d54-24bf1ddb5917	{"name": "GENERAL ASGG 24 CGAA-B 2.0T INV AC 5*", "brand": "GENERAL", "model": "ASGG 24 CGAA-B 2.0T INV AC 5*", "opening_stock_qty": 0}	\N	2026-10-09 17:54:09.133437+05:30
c67d0789-7fa4-45e2-b426-2437ff3d747b	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	BULK_PRODUCTS_CREATED	product	ebcb61f5-5f10-4df6-809a-a5d81b383fbe	{"brand": "TEST_BRAND", "models": ["MOD_001", "MOD_002"], "category_id": "a61627a9-d0a7-49b8-af5f-56c872026561", "category_name": "AC", "created_count": 2, "skipped_count": 0}	\N	2026-10-09 18:18:13.847905+05:30
fc69277d-b517-48f3-962a-187b1dad9e41	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	BULK_PRODUCTS_CREATED	product	044e780d-37ab-4bfb-a93f-28d135453547	{"brand": "HAIER", "models": ["AC HAIER HS12C-TCS3B 1T 3* (INV)", "HS12V-AOW3BN-INV:AC", "HS 12V PNW3BN-INV AC", "HS 13C POW3BN-INV:AC", "HS13E-TXG5B(INV):AC", "HS13K-PYG5BE-INV:AC", "HS13K-PZB3BN-INV:AC", "HS 18EP-TXS5BN-INV:AC", "HS19E-TXW5BN-INV:AC", "HSI 12VP-S3NB-I:AC", "HSI 13VP-G3NB-I:AC", "HSI 14EHD-GAI5NB-I:AC", "HSI 14KU-CAI4NB-I:AC", "HSI 19EHD-GAI5NB-I:AC", "HSI 48N-G3NB-I:AC", "HSI 48VP-S3NB-I:AC", "HSI 50CP-S3NB-I:AC"], "category_id": "a61627a9-d0a7-49b8-af5f-56c872026561", "category_name": "AC", "created_count": 17, "skipped_count": 0}	\N	2026-10-09 18:35:03.742715+05:30
cb3971a1-6654-4c08-948d-75bbe4b3117e	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	CATEGORY_CREATED	category	360e12f4-e4b9-4a67-9169-290f2ac8dc67	{"name": "AIR FRYER", "has_dual_serial": false}	\N	2026-10-09 18:35:58.260405+05:30
c973950e-aca7-42ce-89fd-24273c9d6af4	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	BULK_PRODUCTS_CREATED	product	c27f679f-759c-4bd6-b0b1-038cd6d5aec2	{"brand": "HAIER", "models": ["HAF-D503B:PIP", "HAF-M403I:PIP"], "category_id": "a61627a9-d0a7-49b8-af5f-56c872026561", "category_name": "AC", "created_count": 2, "skipped_count": 0}	\N	2026-10-09 18:36:29.813714+05:30
a634b98c-ff41-4a41-b540-3020afaea8ef	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_UPDATED	product	d3dc8b67-a0ed-436f-965f-013c4f1e9efc	{"name": "HAIER HAF-M403I:PIP", "is_active": true}	\N	2026-10-09 18:37:10.85252+05:30
4db0317b-c5e6-40e3-aa7d-5412765d8330	656f2005-9e50-4d61-9009-e9356e0a9c46	\N	PRODUCT_UPDATED	product	c27f679f-759c-4bd6-b0b1-038cd6d5aec2	{"name": "HAIER HAF-D503B:PIP", "is_active": true}	\N	2026-10-09 18:37:29.504476+05:30
\.


--
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.categories (id, name, is_active, created_at, updated_at, has_dual_serial) FROM stdin;
a61627a9-d0a7-49b8-af5f-56c872026561	AC	t	2026-10-08 16:00:02.724115+05:30	2026-10-08 16:00:02.724115+05:30	t
3866bb27-b9b4-40c1-99b8-2aed06198a18	REFERIGERATOR	t	2026-10-08 16:03:02.90933+05:30	2026-10-08 16:03:02.90933+05:30	f
043d664f-f89e-4187-99f0-ff9bceb2575c	TV	t	2026-10-08 16:03:49.907974+05:30	2026-10-08 16:03:49.907974+05:30	f
5d3395d9-808e-4fff-815c-a0facdf8bbdb	FREEZER	t	2026-10-08 16:58:41.867432+05:30	2026-10-08 16:58:41.867432+05:30	f
360e12f4-e4b9-4a67-9169-290f2ac8dc67	AIR FRYER	t	2026-10-09 18:35:58.260405+05:30	2026-10-09 18:35:58.260405+05:30	f
c0f349e1-9209-422e-b304-a5f3d0bbf5b8	SEMI WM	t	2026-10-08 16:02:46.527857+05:30	2026-10-08 16:02:46.527857+05:30	f
\.


--
-- Data for Name: devices; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.devices (id, device_uid, label, approved_by_id, approved_at, is_active, created_at) FROM stdin;
14a77e6e-6251-4bf8-b839-519260e205ae	0300630b-cb12-4010-af1e-1c414df029f1	Android Godown Scanner	656f2005-9e50-4d61-9009-e9356e0a9c46	2026-10-08 13:14:39.15632+05:30	t	2026-10-08 13:14:14.039885+05:30
e5621cd5-aaa0-40f3-9e5f-6c02b89d0d0a	16b82feb-9760-4ded-a520-6d92be809377	Android Godown Scanner	656f2005-9e50-4d61-9009-e9356e0a9c46	2026-10-08 16:39:58.398456+05:30	t	2026-10-08 16:38:56.960664+05:30
\.


--
-- Data for Name: inward_batches; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inward_batches (id, product_id, invoice_reference, transaction_date, received_by_user_id, device_id, quantity, remarks, created_at, inward_type) FROM stdin;
\.


--
-- Data for Name: inward_lines; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inward_lines (id, batch_id, serial_number_id, created_at) FROM stdin;
\.


--
-- Data for Name: outward_batches; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.outward_batches (id, product_id, shop_id, delivery_reference, transaction_date, dispatched_by_user_id, device_id, quantity, matched_count, unmatched_count, flagged_count, remarks, created_at, bill_number) FROM stdin;
\.


--
-- Data for Name: outward_lines; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.outward_lines (id, batch_id, serial_text, serial_number_id, product_id, shop_id, transaction_date, is_matched, is_flagged_for_review, flag_reason, created_at, unit_type) FROM stdin;
\.


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) FROM stdin;
4c32c360-3147-44e1-b8f6-4ade7ab898b1	FORMENTY LED FMTY -FM55UHDQTVDXB5 GOOGLE Q LED TV VELORA	\N	043d664f-f89e-4187-99f0-ff9bceb2575c	FORMENTY	LED FMTY -FM55UHDQTVDXB5 GOOGLE Q LED TV VELORA	\N	piece	t	\N	0	0	f	t	2026-10-09 11:34:05.174657+05:30	2026-10-09 11:34:05.174657+05:30
48f9f792-e076-4970-9506-fd1c589a344c	FORMENTY AC FMTY Split Inverter FRIO 1.0T3*-Fm12ininv3froed	\N	a61627a9-d0a7-49b8-af5f-56c872026561	FORMENTY	AC FMTY Split Inverter FRIO 1.0T3*-Fm12ininv3froed	\N	piece	t	\N	0	0	f	t	2026-10-09 17:46:02.662567+05:30	2026-10-09 17:46:02.662567+05:30
c470be68-a897-4619-a664-8de8de92bf20	CARRIER AC MIDEA 12K SANTIS NXG (V-PRO) DLX INV 1 TON 3*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	CARRIER	AC MIDEA 12K SANTIS NXG (V-PRO) DLX INV 1 TON 3*	\N	piece	t	\N	0	0	f	t	2026-10-09 17:48:52.548906+05:30	2026-10-09 17:48:52.548906+05:30
944814a5-6009-4f50-b13e-131dad62243e	CARRIER CARRIER AC 12K XCEL EDGE GXI INV AC 5*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	CARRIER	CARRIER AC 12K XCEL EDGE GXI INV AC 5*	\N	piece	t	\N	0	0	f	t	2026-10-09 17:49:38.784396+05:30	2026-10-09 17:49:38.784396+05:30
26d7311e-4fe3-49bf-bd63-037cf843adbf	GENERAL ASSGG24CGWA-B 2T INV AC 4*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASSGG24CGWA-B 2T INV AC 4*	\N	piece	t	\N	0	0	f	t	2026-10-09 17:53:04.802408+05:30	2026-10-09 17:53:04.802408+05:30
5afc04e5-5ae4-4f5e-8757-24c9942f0e96	GENERAL ASGG 24 CPAB-B 3*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGG 24 CPAB-B 3*	\N	piece	t	\N	0	0	f	t	2026-10-09 17:53:47.19933+05:30	2026-10-09 17:53:47.19933+05:30
94a0f4bd-acc7-40bc-832b-b4e1b4afae85	GENERAL ASGG 22CNWA-B 1.8T INV AC 3*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGG 22CNWA-B 1.8T INV AC 3*	\N	piece	t	\N	0	0	f	t	2026-10-09 17:55:29.869288+05:30	2026-10-09 17:55:29.869288+05:30
2f6867f2-d0a6-4f11-91cc-06d9eda1e250	GENERAL ASGG 18 CKWA-B 1.5T INV AC 3*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGG 18 CKWA-B 1.5T INV AC 3*	\N	piece	t	\N	0	0	f	t	2026-10-09 17:56:28.124602+05:30	2026-10-09 17:56:28.124602+05:30
7f4ac78e-a27b-428d-8d41-09e90e30beb2	ROCKWELL GFR1210F	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	GFR1210F	\N	piece	t	\N	0	0	f	t	2026-10-08 16:59:02.587912+05:30	2026-10-08 16:59:17.376888+05:30
b3c1b461-b0f1-4c8e-9dbe-8dd56d2e6a95	ROCKWELL GFR 450 DDUC-5S	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	GFR 450 DDUC-5S	\N	piece	t	\N	0	0	f	t	2026-10-08 16:59:51.604125+05:30	2026-10-08 16:59:51.604125+05:30
434b9a12-b1bf-4628-92eb-d8c334d06686	ROCKWELL GFR 550 DDUC5S	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	GFR 550 DDUC5S	\N	piece	t	\N	0	0	f	t	2026-10-08 17:00:26.890128+05:30	2026-10-08 17:00:26.890128+05:30
79506c87-6018-4ea5-9b28-6462f32ade86	ROCKWELL GFR 550 DDUCSS5S	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	GFR 550 DDUCSS5S	\N	piece	t	\N	0	0	f	t	2026-10-08 17:00:55.19106+05:30	2026-10-08 17:00:55.19106+05:30
67a2e9f1-233d-4ea7-a576-5fc33861d833	ROCKWELL RVC 1100	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	RVC 1100	\N	piece	t	\N	0	0	f	t	2026-10-08 17:02:45.326261+05:30	2026-10-08 17:02:45.326261+05:30
67303761-7b54-48c5-8f2a-3898a2a33a48	CARRIER AC CARRIER 18K INDUS GXI ALPHA HYBRIDJET 1.5 TON 3*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	CARRIER	AC CARRIER 18K INDUS GXI ALPHA HYBRIDJET 1.5 TON 3*	\N	piece	t	\N	0	0	f	t	2026-10-09 17:48:06.262595+05:30	2026-10-09 17:48:06.262595+05:30
a2943f0e-4eac-4199-bec0-b45cdb2e2a96	CARRIER CARRIER 24K XCEED EDGE GXIINV AC 5*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	CARRIER	CARRIER 24K XCEED EDGE GXIINV AC 5*	\N	piece	t	\N	0	0	f	t	2026-10-09 17:49:21.769679+05:30	2026-10-09 17:49:21.769679+05:30
90492d3d-ac36-4a1f-bc8f-b9005c976939	CARRIER CARRIER AC 24K XCEED EDGE GXI ALPHA HYBRIDJET 3*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	CARRIER	CARRIER AC 24K XCEED EDGE GXI ALPHA HYBRIDJET 3*	\N	piece	t	\N	0	0	f	t	2026-10-09 17:49:52.37412+05:30	2026-10-09 17:49:52.37412+05:30
63bea063-3723-4969-9d54-24bf1ddb5917	GENERAL ASGG 24 CGAA-B 2.0T INV AC 5*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGG 24 CGAA-B 2.0T INV AC 5*	\N	piece	t	\N	0	0	f	t	2026-10-09 17:54:09.133437+05:30	2026-10-09 17:54:09.133437+05:30
044e780d-37ab-4bfb-a93f-28d135453547	HAIER AC HAIER HS12C-TCS3B 1T 3* (INV)	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	AC HAIER HS12C-TCS3B 1T 3* (INV)	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
bbc8d408-98e5-4e2c-ac47-3d87abdb0b22	HAIER HS12V-AOW3BN-INV:AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HS12V-AOW3BN-INV:AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
13d1a500-00c5-4b32-b5b0-e45a43aced97	HAIER HS 12V PNW3BN-INV AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HS 12V PNW3BN-INV AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
2619236d-4e53-476f-8a30-2489b22dd25b	HAIER HS 13C POW3BN-INV:AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HS 13C POW3BN-INV:AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
83c70fe6-10de-44ae-a2f7-df1341f9958a	HAIER HS13E-TXG5B(INV):AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HS13E-TXG5B(INV):AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
894dfc6c-5206-4753-865e-5dbf4cf6d369	HAIER HS13K-PYG5BE-INV:AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HS13K-PYG5BE-INV:AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
832428eb-1af6-4b3c-b49d-e65608301e63	HAIER HS13K-PZB3BN-INV:AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HS13K-PZB3BN-INV:AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
9b6d99ae-b6dd-4518-ba67-2608c30655d1	HAIER HS 18EP-TXS5BN-INV:AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HS 18EP-TXS5BN-INV:AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
e298d87c-cce3-4c23-931c-2031a968a5cc	HAIER HS19E-TXW5BN-INV:AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HS19E-TXW5BN-INV:AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
d1a682f7-4aaf-4f85-8dcb-236368d35256	HAIER HSI 12VP-S3NB-I:AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HSI 12VP-S3NB-I:AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
305f02d8-7245-499d-a98f-5d95c7a1d8c1	HAIER HSI 13VP-G3NB-I:AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HSI 13VP-G3NB-I:AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
2b8908cb-64e9-4b28-abbb-81bddb415f2c	HAIER HSI 14EHD-GAI5NB-I:AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HSI 14EHD-GAI5NB-I:AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
381fc5ab-1b66-430f-921a-1ace032eb8c3	HAIER HSI 14KU-CAI4NB-I:AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HSI 14KU-CAI4NB-I:AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
a77f1c84-5d51-4bd7-b71e-a6d4c25e53af	HAIER HSI 19EHD-GAI5NB-I:AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HSI 19EHD-GAI5NB-I:AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
4f7dd0f2-62e5-4bb8-b2c3-50f6e61e0a2a	HAIER HSI 48N-G3NB-I:AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HSI 48N-G3NB-I:AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
366fba52-56dc-45d4-a4dd-68cc63691d8e	HAIER HSI 48VP-S3NB-I:AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HSI 48VP-S3NB-I:AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
b0e0bb06-1895-45b3-b2a1-9924e3985fe7	HAIER HSI 50CP-S3NB-I:AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	HAIER	HSI 50CP-S3NB-I:AC	\N	piece	t	\N	0	0	f	t	2026-10-09 18:35:03.742715+05:30	2026-10-09 18:35:03.742715+05:30
d3dc8b67-a0ed-436f-965f-013c4f1e9efc	HAIER HAF-M403I:PIP	\N	360e12f4-e4b9-4a67-9169-290f2ac8dc67	HAIER	HAF-M403I:PIP	\N	piece	t	\N	0	0	f	t	2026-10-09 18:36:29.813714+05:30	2026-10-09 18:37:10.85252+05:30
c27f679f-759c-4bd6-b0b1-038cd6d5aec2	HAIER HAF-D503B:PIP	\N	360e12f4-e4b9-4a67-9169-290f2ac8dc67	HAIER	HAF-D503B:PIP	\N	piece	t	\N	0	0	f	t	2026-10-09 18:36:29.813714+05:30	2026-10-09 18:37:29.504476+05:30
0cc42ac9-3e11-4609-9075-fbc5e90bf39c	ROCKWELL GFR 910 UC5S	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	GFR 910 UC5S	\N	piece	t	\N	0	0	f	t	2026-10-08 17:01:52.374719+05:30	2026-10-08 17:01:52.374719+05:30
4f7e752a-a900-4279-a7f3-bdd59c7e4887	ROCKWELL ROCKWELL MB-100	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	ROCKWELL MB-100	\N	piece	t	\N	0	0	f	t	2026-10-08 17:02:27.009787+05:30	2026-10-08 17:02:27.009787+05:30
acb37210-eb8a-4759-b4f0-fb46e2a90e7a	ROCKWELL RVC 400	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	RVC 400	\N	piece	t	\N	0	0	f	t	2026-10-08 17:03:13.350828+05:30	2026-10-08 17:03:13.350828+05:30
72aa311b-e0c8-4a6f-8d9e-80c9c5cad30f	ROCKWELL RVC 550	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	RVC 550	\N	piece	t	\N	0	0	f	t	2026-10-08 17:03:59.677214+05:30	2026-10-08 17:03:59.677214+05:30
8d2b048f-fb53-476e-82e4-caba8d509b76	ROCKWELL RVC 700	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	RVC 700	\N	piece	t	\N	0	0	f	t	2026-10-08 17:04:13.25429+05:30	2026-10-08 17:04:13.25429+05:30
2a6fb377-44d5-4b58-9882-6a4e69839104	ROCKWELL SFR 250 SDU-4S	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	SFR 250 SDU-4S	\N	piece	t	\N	0	0	f	t	2026-10-08 17:04:40.124677+05:30	2026-10-08 17:04:40.124677+05:30
e005dfbd-c056-416f-8fb9-74067e0a4659	ROCKWELL SFR 350 DDU5S	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	SFR 350 DDU5S	\N	piece	t	\N	0	0	f	t	2026-10-08 17:05:34.143567+05:30	2026-10-08 17:05:34.143567+05:30
98c6d742-2bce-4e95-9ba6-daa72bebd5f0	ROCKWELL SFR 350GTS LED	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	SFR 350GTS LED	\N	piece	t	\N	0	0	f	t	2026-10-08 17:06:10.005308+05:30	2026-10-08 17:06:10.005308+05:30
7449ebcc-8d69-42c3-8df2-d20a0c37a96c	ROCKWELL SFR 450 DDU-5S	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	SFR 450 DDU-5S	\N	piece	t	\N	0	0	f	t	2026-10-08 17:06:24.958425+05:30	2026-10-08 17:06:24.958425+05:30
26eca82c-bd82-4819-a3c9-cab776834bfb	ROCKWELL SFR 450 GTS LED	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	SFR 450 GTS LED	\N	piece	t	\N	0	0	f	t	2026-10-08 17:06:49.050572+05:30	2026-10-08 17:06:49.050572+05:30
5dfb33bf-2c0a-40c2-a340-448ad9c825d5	ROCKWELL SFR 550 DDU5S	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	SFR 550 DDU5S	\N	piece	t	\N	0	0	f	t	2026-10-08 17:07:04.86483+05:30	2026-10-08 17:07:04.86483+05:30
bacc9a8e-8ce2-455f-9166-809aba107dfa	ROCKWELL SFR 750 TDU5S	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	SFR 750 TDU5S	\N	piece	t	\N	0	0	f	t	2026-10-08 17:08:46.137962+05:30	2026-10-08 17:08:46.137962+05:30
0fd5dc56-f051-441c-a32f-031aa85c4438	ROCKWELL GFR 910 UC5S	\N	5d3395d9-808e-4fff-815c-a0facdf8bbdb	ROCKWELL	GFR 910 UC5S	\N	piece	t	\N	0	0	f	f	2026-10-08 17:01:12.983859+05:30	2026-10-08 17:12:18.722915+05:30
b98ff282-df28-4a8b-962f-0da93398777c	GENERAL 12CGWA-B 1.0T INV AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	12CGWA-B 1.0T INV AC	\N	piece	t	\N	0	0	f	t	2026-10-08 17:13:23.323547+05:30	2026-10-08 17:13:23.323547+05:30
3f5872a1-df35-4bf7-85b4-22cc53085f79	GENERAL ASGA 18 BMAA-B 1.5T Split Ac	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGA 18 BMAA-B 1.5T Split Ac	\N	piece	t	\N	0	0	f	t	2026-10-08 17:13:51.763891+05:30	2026-10-08 17:13:51.763891+05:30
8811c429-0cf7-477f-ada4-18fdaa1beee1	GENERAL ASGA18BUTA-B	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGA18BUTA-B	\N	piece	t	\N	0	0	f	t	2026-10-08 17:14:29.48848+05:30	2026-10-08 17:14:29.48848+05:30
43fd84b0-ee86-4411-9d4c-0a0ac31959af	GENERAL ASGA 24 BMAA-B 2.0T Split Ac	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGA 24 BMAA-B 2.0T Split Ac	\N	piece	t	\N	0	0	f	t	2026-10-08 17:14:09.64954+05:30	2026-10-08 17:14:46.283152+05:30
09582965-46f7-4019-bba0-7161ec1cfeb3	GENERAL ASGA24BUTA-B 2T	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGA24BUTA-B 2T	\N	piece	t	\N	0	0	f	t	2026-10-08 17:15:02.38574+05:30	2026-10-08 17:15:02.38574+05:30
03aca04a-fcf1-4708-bbac-074130fc2c0f	GENERAL ASGG 12CGAB-B 1T INV AC	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGG 12CGAB-B 1T INV AC	\N	piece	t	\N	0	0	f	t	2026-10-08 17:15:32.1243+05:30	2026-10-08 17:15:32.1243+05:30
2466d044-b519-4a59-92f5-67a261d23b44	GENERAL ASGG 12 CGTB   1 Tn 5*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGG 12 CGTB   1 Tn 5*	\N	piece	t	\N	0	0	f	t	2026-10-08 17:16:00.841635+05:30	2026-10-08 17:16:00.841635+05:30
f306cbd1-f4fb-45e2-b408-ab8cb46e536b	GENERAL ASGG12CGWA-B 1 T INV AC 4*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGG12CGWA-B 1 T INV AC 4*	\N	piece	t	\N	0	0	f	t	2026-10-08 17:16:18.57077+05:30	2026-10-08 17:16:18.57077+05:30
953f64bb-183a-4dcc-ad51-4a9b8d1ba754	GENERAL ASGG 12 CKWA-B 1.OT INV AC 3*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGG 12 CKWA-B 1.OT INV AC 3*	\N	piece	t	\N	0	0	f	t	2026-10-08 17:16:40.348617+05:30	2026-10-08 17:16:40.348617+05:30
06521486-9173-4469-a926-09fdde8f7fba	GENERAL ASGG 12 CPWA-B 1T INV AC3*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGG 12 CPWA-B 1T INV AC3*	\N	piece	t	\N	0	0	f	t	2026-10-08 17:17:23.484745+05:30	2026-10-08 17:17:23.484745+05:30
03316b63-3179-42e1-9210-df9a792649a9	GENERAL ASGG 18 CEAC-B 1.5T INC AC 5*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGG 18 CEAC-B 1.5T INC AC 5*	\N	piece	t	\N	0	0	f	t	2026-10-08 17:17:40.86429+05:30	2026-10-08 17:17:40.86429+05:30
a644739a-efcc-47fb-8117-bcfc36c4b41e	GENERAL ASGG 18 CETB-B 1.5T INV AC 5*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGG 18 CETB-B 1.5T INV AC 5*	\N	piece	t	\N	0	0	f	t	2026-10-08 17:18:02.716345+05:30	2026-10-08 17:18:02.716345+05:30
4958f751-6916-45fc-8725-d0bf223ac9c9	FORMENTY LED FMTY FM32HDSQTVDXB1 Google Q Led VELORA	\N	043d664f-f89e-4187-99f0-ff9bceb2575c	FORMENTY	LED FMTY FM32HDSQTVDXB1 Google Q Led VELORA	\N	piece	t	\N	0	0	f	t	2026-10-09 11:32:19.460036+05:30	2026-10-09 11:32:19.460036+05:30
730cc975-b1e6-48b6-94dc-8f5686b98c7a	FORMENTY LED FMTY -FM32HDSQTVWWCR GOOGLE Q LED TV -Cinara	\N	043d664f-f89e-4187-99f0-ff9bceb2575c	FORMENTY	LED FMTY -FM32HDSQTVWWCR GOOGLE Q LED TV -Cinara	\N	piece	t	\N	0	0	f	t	2026-10-09 11:32:31.151671+05:30	2026-10-09 11:32:31.151671+05:30
9ab2a8e4-e693-47f2-9024-c1a791556c8f	FORMENTY LED FMTY FM40FDSQTVDXB2 Google Q Led VELORA	\N	043d664f-f89e-4187-99f0-ff9bceb2575c	FORMENTY	LED FMTY FM40FDSQTVDXB2 Google Q Led VELORA	\N	piece	t	\N	0	0	f	t	2026-10-09 11:33:14.210849+05:30	2026-10-09 11:33:14.210849+05:30
73cfffaa-0a4c-4841-8df0-9a5a9393b343	FORMENTY LED FMTY FM43UHDQTVDXB4 4K UHD Q LED VELORA	\N	043d664f-f89e-4187-99f0-ff9bceb2575c	FORMENTY	LED FMTY FM43UHDQTVDXB4 4K UHD Q LED VELORA	\N	piece	t	\N	0	0	f	t	2026-10-09 11:33:47.619372+05:30	2026-10-09 11:33:47.619372+05:30
8590701f-97f0-486e-9b47-ced013bd4c1d	FORMENTY FM32HDSQSPR1DX Q LED-SPECTRA SERIES	\N	043d664f-f89e-4187-99f0-ff9bceb2575c	FORMENTY	FM32HDSQSPR1DX Q LED-SPECTRA SERIES	\N	piece	t	\N	0	0	f	t	2026-10-09 11:30:41.699172+05:30	2026-10-09 15:03:17.648094+05:30
8531cbb7-5457-49c3-9e0d-4529700e42bf	FORMENTY FM55UHDQSPR5DX Q LED- SPECTRA SERIES	\N	043d664f-f89e-4187-99f0-ff9bceb2575c	FORMENTY	FM55UHDQSPR5DX Q LED- SPECTRA SERIES	\N	piece	t	\N	0	0	f	t	2026-10-09 11:31:11.920615+05:30	2026-10-09 13:40:00.804401+05:30
7999322a-f1bb-4a0f-a72e-475b819b6a3f	FORMENTY FM43UHDQSPR4DX QLED-SPECTRA SERIES	\N	043d664f-f89e-4187-99f0-ff9bceb2575c	FORMENTY	FM43UHDQSPR4DX QLED-SPECTRA SERIES	\N	piece	t	\N	0	0	f	t	2026-10-09 11:30:57.553489+05:30	2026-10-09 16:40:49.482871+05:30
00d31b1c-02fe-454f-ad9c-3bd47c74f7d0	FORMENTY LED FMTY FM32HDTVDXB1 GOOGLE  QLED TV VELORA	\N	043d664f-f89e-4187-99f0-ff9bceb2575c	FORMENTY	LED FMTY FM32HDTVDXB1 GOOGLE  QLED TV VELORA	\N	piece	t	\N	0	0	f	t	2026-10-09 11:32:54.063222+05:30	2026-10-09 15:51:33.436686+05:30
f1405e84-41dc-4b22-bd87-bd9006a17c81	FORMENTY FM 32 HDSPT2 SMART	\N	043d664f-f89e-4187-99f0-ff9bceb2575c	FORMENTY	FM 32 HDSPT2 SMART	\N	piece	t	\N	0	0	f	t	2026-10-09 11:30:14.054387+05:30	2026-10-09 15:51:33.436686+05:30
75b4ac90-2d54-4c52-aaae-1c86b6554ae8	FORMENTY FM32HDSPB2YU LED- LUMINOR SERIES	\N	043d664f-f89e-4187-99f0-ff9bceb2575c	FORMENTY	FM32HDSPB2YU LED- LUMINOR SERIES	\N	piece	t	\N	0	0	f	t	2026-10-09 11:30:01.806721+05:30	2026-10-09 15:51:33.436686+05:30
0dd497cc-caf0-4134-9437-535b16365a0b	FORMENTY FM 32 HDRPT1	\N	043d664f-f89e-4187-99f0-ff9bceb2575c	FORMENTY	FM 32 HDRPT1	\N	piece	t	\N	0	0	f	t	2026-10-09 11:29:46.017984+05:30	2026-10-09 16:40:49.482871+05:30
b837c539-50a3-4150-9fe9-919c841edc00	CARRIER AC CARRIER 19K EXCEED LUMO GXI 1.5 T 5*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	CARRIER	AC CARRIER 19K EXCEED LUMO GXI 1.5 T 5*	\N	piece	t	\N	0	0	f	t	2026-10-09 17:48:32.256582+05:30	2026-10-09 17:48:32.256582+05:30
fa8b239a-c9e1-43d7-bf5d-37c9e0a3d0dc	GENERAL ECCGA4 EXTENDED COMPREHNSIVE COVER(F/I/C)4YR	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ECCGA4 EXTENDED COMPREHNSIVE COVER(F/I/C)4YR	\N	piece	t	\N	0	0	f	t	2026-10-09 17:52:48.561338+05:30	2026-10-09 17:52:48.561338+05:30
ea453d9a-85fb-4293-b1cc-2cabf84cd453	GENERAL ASGG30CEAC.B 2.5 T INV AC 5*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGG30CEAC.B 2.5 T INV AC 5*	\N	piece	t	\N	0	0	f	t	2026-10-09 17:53:30.112812+05:30	2026-10-09 17:53:30.112812+05:30
7100a1c9-9c26-447b-b802-c50f699ef157	GENERAL ASGG 24CEAC-B 2T INV AC 5*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGG 24CEAC-B 2T INV AC 5*	\N	piece	t	\N	0	0	f	t	2026-10-09 17:54:22.402935+05:30	2026-10-09 17:54:22.402935+05:30
15b44915-d3de-434f-b570-e4e605161410	GENERAL ASGG 18 CNWA-B 1.5T INV AC 3*	\N	a61627a9-d0a7-49b8-af5f-56c872026561	GENERAL	ASGG 18 CNWA-B 1.5T INV AC 3*	\N	piece	t	\N	0	0	f	t	2026-10-09 17:56:02.364721+05:30	2026-10-09 17:56:02.364721+05:30
\.


--
-- Data for Name: returns; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.returns (id, serial_text, serial_number_id, outward_line_id, shop_id, product_id, return_date, reason, condition, received_by_user_id, device_id, inspection_result, inspected_at, inspected_by_user_id, remarks, created_at) FROM stdin;
\.


--
-- Data for Name: serial_history; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.serial_history (id, serial_number_id, serial_text, action, from_status, to_status, shop_id, inward_batch_id, outward_batch_id, return_id, is_matched, user_id, device_id, remarks, created_at) FROM stdin;
\.


--
-- Data for Name: serial_numbers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.serial_numbers (id, serial_number, product_id, status, last_shop_id, created_at, updated_at, unit_type) FROM stdin;
\.


--
-- Data for Name: shops; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.shops (id, name, city, phone, is_active, created_at, updated_at) FROM stdin;
170c0665-2fea-42e9-83b1-c0942ab66a8e	ANAS HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
78f3422e-c1f3-488f-91c3-2ae5cf10fcfb	BENZY HOSPITALS PRIVATE LIMITED	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
147d17e4-c442-45bd-8ed6-eb8bfdd1afda	DR.DOOR	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
e973e4d6-e6ec-46a6-a6c5-2247c8474297	EVERCOOL ENTERPRISES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
e133a516-2da2-488a-8a73-3d20ae874a6e	FRIENDS COMPUTERS HOME APPLAINCES & SECURITY SYSTEM	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
215d8e77-13dc-45c8-9fea-6e42f318f86f	GODS OWN	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
e78df0a1-ff06-4562-8480-9324b4f44386	GRAND HOME APPLIANCE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
33b85381-ee77-4af2-9454-6aae310142be	HAYATH MEDICAL CENTRE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
c5ee6306-87df-40d5-8974-03d085dd41e7	HELAN DIGITAL MART	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
961e0a25-5b93-4e94-b9ed-5e896865856a	KADOOR ELECTRONICS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
52cb131c-127f-46b4-9d07-0c764fad7979	KALPAKA ELECTRONICS (FRK)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
4105f325-5167-4662-85b7-52c87ca9d471	KALPAKA ELECTRONICS & HOME BAZAR	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
651e2eee-b386-4421-8297-9227d47782e5	Kalpaka Electronics & Home Bazar Mlp	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
1b1a6fa4-1f01-45e0-bb79-fce43eec0d79	Kannankandy Fridge centre	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
d9a3ef12-1788-479b-8c23-e591a9bb5f64	KASIM KUMMALI ADV	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
41a1bd48-9dde-4bf1-a883-a11aec87bdff	KERALA FLIGHT ACADEMY PRIVATE LIMITED	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
5542eea8-9927-4753-af7d-592367c35a1a	MAB TECH EQUIPMENT PRIVATE LIMITED(New)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
2e5f2871-e503-4551-9b72-7c024e878790	Mandhi Palce	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
9395b0c0-9eee-476d-bf15-f1ad038ea120	MANSOOR PATTAMBI	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
a5e9d1e0-ca2e-464b-be64-ba0657462f1e	MERRY SOUL ENTERPRISE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
51684061-ef0c-4945-ba57-bfcd172534e8	Mr YESHUDAS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
942f9953-35ad-47fc-b578-116467a9da39	MUJEEB ARIMBRA	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
8c45386f-9515-4c7b-a7d3-b9400e8ca04e	NESTO HYPER MARKET (CLT)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
99ecb4b9-93ff-455a-aa4a-63b83c102b87	NEW TECH COOLING SOLUTIONS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
5183fb8b-ff36-42b3-ae92-5f2406a411f5	NEW WHITE HOME	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
3ee43a8a-5ce2-4ac1-bbc4-11a7d817c1dd	OMEGA AGENCIES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
bd87ed0b-4421-443f-9738-11e2938b112a	PRAKASH TRADERS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
ca9def0b-53f2-4877-8da6-08a8734f56f5	PV STORE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
02261124-4b60-45d2-88ed-b352a3e53782	PV STORE EKKAPPARAMBU	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
b8902189-720b-488a-a69e-e39f8cb776c0	REAL AGENCY	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
0bb53a80-ef53-4ffd-a3f2-0e66722f75a0	RETAIL BILL	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
bc506a19-54ba-4591-a790-072ecb025d3a	RIYAS ROK	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
da6afebb-a34e-4130-acbb-ad549dc39797	SHAMEER PANDI	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
d599b94b-56bc-4817-98f7-ea68f10192cb	SIGMA ELECTRONICS MANJERI	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
48bbd731-0af1-4d39-bd80-34edcd586451	SMART HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
c80d3ae4-80f0-4f41-bbc7-dcf703b2fbc9	S.P TRADERS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
0988fa72-e24a-4a06-85f2-dca3633d8338	VAVA FURNITURE AND HOME APPLIANCES(New)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
d0388df3-a68a-4386-8b89-68b7ad618b6d	VK GROUP	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
13182244-6bf1-46f8-b9d7-aa5668c96474	AKAM  HOME APPLIANCES & MOBILES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
91d8d12b-9d9c-41cb-9e66-26994ea2f391	A K M STORE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
cd8e88d6-c542-4cc4-b198-077ba84517bd	ASHIKH ELECTRONIC AND HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
c1168439-f218-495e-b5e7-faf41a7fd7b4	Brand House Agencies	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
286c740c-6798-4171-b348-e9aa009c9bbf	BROTHERS HOME APPLAINES & FURNITURE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
9b6124d1-1db2-4f4b-8af3-fdfde5376f8c	BUDGET FURNITURE & HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
49a7ce98-4b80-4365-83ac-af541523136b	BUDGET FURNITURE & HOME APPLIANCES (PNKD)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
628c3501-0a7e-4e9e-bec3-6eaada3be7dd	CHOICE HOME SERVICES (Mtvlr)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
8e31ca61-2413-4a9a-aef6-3cd78bb51365	Cool India Home Needs & Appliances	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
9200f890-cb62-4e9c-830b-deb2616c7112	Cool Makers	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
5d15aab7-2243-4b14-9f55-e3e005a3e794	DIGITAL MART	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
226aa1ff-d73d-474b-933a-954919a2d72b	Digital Mart (Kvnr)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
6fc8ac8b-53f5-425e-97df-97cfd6babebc	Dream Digital	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
acc58f7c-5bb7-43ea-a182-4ac94793a4c2	ELECTRO WORLD FRIDGE HOUSE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
b76069a5-19d2-4f23-8e01-a14b13e6507e	ELITE METALS & HOME NEEDS  MJRY	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
eb77f472-76c4-473c-8df4-1b254ce209b4	E MAX DIGITAL	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
b7f69469-7b51-405a-ae5a-800b94c3dfef	E WORLD Home Appliances(New)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
cf11c47f-bb0d-4853-b791-44a2a6cce1a5	FAMILY HOMELAND ELECTRICALS & SANITARY	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
5e3b7195-1858-4a15-8e27-2ecf40d1efad	FAMILY METALS & FURNITURE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
5c3c51b1-9e93-46ba-9008-ef6837c4d151	FOCUS FURNITURE & ELECTRONICS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
663f7392-6b62-4bc8-824b-f7d5c28c1de2	FRIDGE HOUSE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
e61aaa32-135e-4bfa-8567-994fe792952e	GK ENTERPRISES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
82e32476-a919-498c-873e-b9d01dfd5424	HAPPY HOME	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
c97c85f6-ea96-4191-8a53-547a778e3e56	Happy Home Hardware & Electricals	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
daae6f0a-f360-47f8-b744-79d3c6c40dbb	HI MART HYPERMARKET	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
1e5828e8-267b-494d-bcd6-537563802d72	HOME CHOICE WNDR	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
eb2a2c34-1dcb-4c32-b85c-caa2a4ba372b	HOME Q DIGITAL ELECTRONICS& HOME	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
7b9faec4-d2c9-46bd-b276-b10fbdf0eb7b	HOMY SMART HOME	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
28a098be-827f-4ed9-aa01-a9de1d99ba76	J J KOCHUKUDIYIL	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
803c16a2-7eef-4db3-9ff1-8ca2eb133823	Kaippally Home Appliances	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
1ceaddba-3435-41f3-8d39-604cb20091d6	KALYANI E MART (New)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
3723884f-2b3a-4bc3-8140-b62ebdf89a7b	K C APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
d0fe4a78-8d59-4e3b-9cbb-e969b7d8b42a	KISWAH HOME GUIDE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
a46422e8-eb89-4b1f-aac1-49894d0b13bf	KOCHUKUDIYIL AGENCIES NILAMBUR	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
e646ae29-f3e0-49cd-8594-8d42492cd5d8	KOCHUS GALLERY	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
9d4bfd67-1e6f-4035-8528-a0d2a78a36ff	KODUVALI FURNITURE (New)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
d9b0ab81-a6e9-4b65-aff3-cd0d440d203e	Koduvally Furniture	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
af10cfda-b3e1-4a54-8689-f2d575591d60	KOLAR MILL STORES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
c55962fc-fbe9-4f2b-8804-ed398938595b	KRIPA HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
e0a8e43b-eb7f-4839-899f-37d43b566e32	KURIKKAL AGENCIES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
746d23a9-fb20-47ae-8f06-41ed2728f509	Lavanya's Hyper Shoppe	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
39a406cb-6691-460f-9447-368f71e0330d	LAVANYA E PLAZA	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
7a384d7f-1013-4678-91d7-cfa1fa742044	MADATHIL METALS AND HOME NEEDS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
6626c9c2-1990-4133-8fd8-540b6819666b	MANGO DIGI-HUB	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
3c1ab308-a9ce-47d4-b4e3-916ab6ad1cf3	MARVEL  APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
e6810a9b-6f97-4386-b8c8-9a009f576054	MP MART LLP	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
e5b33484-3ea5-402d-a9e7-041e6b968775	NAMBOOTHIRI`S	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
337e4c21-d0d5-4195-88b5-0c812a504b9b	Nero Cold (Ktpdm)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
a2b57457-da3d-4e09-9799-f5e60e5cdee4	NERO COLD LLP	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
d35af958-d089-4fed-8576-231e48b7e168	Nero Cold (New)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
202c9ec3-d912-4862-b79c-4d8b65f8a515	NEW KOCHUKUDIYIL AGENCIES KKV	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
f5c37a5f-ce5d-4650-8dbb-5bf2d246a72e	NEW WAY CENTRE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
a540cb60-8d9d-4ce6-b43e-72b596f4315e	PALLISSERY HOME NEEDS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
7846e503-c907-4dd8-a5e1-b4e077d5120e	P.B.S.DISTRIBUTION	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
52275927-e957-4fa8-a459-ab0c18915ce0	POOTHANARI FURNITURE & ELECTRONICS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
ec802f21-9ae8-4e08-a7ae-c5ef52baa81f	RAJADHANI ELECTRONICS AND HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
72ffe867-63df-4a05-9f50-2f0916449627	RAJADHANI FURNITURE & HOME NEEDS KKV	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
1f922a92-15dd-4d7e-8701-8b381ffb6b8a	SA Agency Home Appliance	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
d61df91a-6086-43ba-b0e7-3fade9408328	SHAHID METALS & HOME NEEDS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
5381e384-f55a-4da3-b2ab-55f2fca7a32a	SHAJAHAN TV&FRIDGE HOUSE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
d4509540-2b73-470a-b4ca-353495e829e3	Sharafiya Electronics Home Needs	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
bb8f5724-ac68-4687-9d23-e7476bb8211e	SREE VINAYA AGENCY	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
28bb1864-a4b6-40e0-a5a2-e92e6e362f61	TM HOME APPLIANCES AND FURNITURE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
97cbeb14-0f80-493a-ab23-db0b10ec256d	ZODIAC ELECTRONICS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
160b6549-2c49-4046-a7d7-1fcaf0ef6a73	AIWA COLLECTION & DISTRIBUTIONS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
967b9347-320f-4987-85e0-c6a23d20a009	AMAN FURNITURE & HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
3728c736-0a14-402c-a8d1-76c59526d54d	BIG BUY COOLING SOLUTIONS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
b41c4b20-1e8c-4221-8efc-1a74f3f51921	CHOICE HOME SELECTION (CHAPNGDI)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
30184c61-99d1-414a-ad6c-5dbe3d491320	CLASSICO HOME APPLIANCES(Bymnt)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
391debdf-b888-4669-8445-108dac6bf9fe	CLASSICO HOME CENTRE (EDPL)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
64a284d8-017f-4244-97b6-26c71740f1e3	CLASSICO HOME CENTRE (KTND)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
fc5442d3-4aa5-451e-afa1-f33e210f0ae9	CLASSICO HOME CENTRE (VLRY)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
10d7df93-f73e-4cf8-aa30-59aca14953ad	CRYSTAL AGENCIES&HOME APPLIANCES(VGA)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
d9a34934-ddc9-4fbc-8f7c-85a5c7b186c9	CRYSTAL MART HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
6b4aeb2f-0f49-4a42-9f1f-c553573ac637	CRYSTAL MART HOME APPLIANCES(New)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
29bd7027-a5d3-47dc-94d6-614aa3240793	DIYA FURNITURE & HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
7115f538-d719-412c-bdcf-1235525e3164	DUBAI MARKET	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
301ac0d5-d265-487e-87d3-f69dce935cfe	Easy installment	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
94b3d974-548c-462e-b218-c5cdbc81ad0a	EMARALD AGENCIES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
ae3fde95-927e-47da-aabc-97605baed1fd	E WORLD ELECTRONICS AND CROCKERY	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
9e729f36-d69c-45df-b562-ed8432e63bf7	E World Home Appliances	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
39630e79-f5fd-4ea6-a50a-1f11c5923e89	E ZONE ELECTRONICS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
00df384d-3a1f-4063-8782-e462685078b7	FAHIDHA  MOODAL	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
f71ada57-b912-48d1-a88e-a60dfc2eeabe	HAPPY EMART	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
d540d6b0-342a-48f3-9375-7dec6573ae35	HOME CENTRE(NEW)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
c0bb908e-1016-40f3-b634-91d3836d03bd	HOME CITY FURNITURE & HOME APPLIANCE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
e24ab17f-c751-45ed-bb20-3da96bb71f2a	HOMEZO FURNITURE AND HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
8724a852-743a-46ea-bd4f-d7077994b809	HOME ZONE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
6cdbff98-49b9-43d8-a02f-1eaa55a2645d	INFRA DIGITAL MART FACTORY OUT LET	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
24a4a36c-617a-4137-b38f-2a770903bedd	JAMJOOM SUPER MARKET PRIVATE LIMITED	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
3b45fee0-1cae-46f2-8f90-b73f08145392	Kattil Home Appliance	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
c38975ad-c2e5-4d1c-a5e5-292b975c8bb4	KATTIL HOME APPLIANCE (Pmblpdk)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
b62c5377-12a3-4dfe-b52b-ab96e5ea04d0	KATTIPARUTHY HOME GUIDE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
76a5e0f1-79be-4be1-a675-67bb51df5ecf	KILIYAMANNIL HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
a1d4c145-0147-4da7-8185-dcf23905de1e	Linear marketing	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
68c6efb7-f8de-407a-b297-b31166ef63eb	M K DIGITAL AND HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
0201be88-683d-4f00-beb8-f009ebab8abf	NEXT SHOW HOME APPLIAINCES & ELECTRONICS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
b3df6aed-9e80-4f69-ab25-f1bba10a6036	OASIS AGENCIES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
6bceecad-5895-474c-97d2-0f20388b7466	PARAMMAL HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
05127127-b43f-4147-8d07-96ddec1e0015	SANA HOME BAZAR (PUTHANATHANI)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
91acbf99-0d5d-43dc-95fa-6c58edcec1a2	SH ELECTRONICS & HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
21a1569d-8818-4669-9035-1abb248e098d	S P BUSINESS ASSOCIATES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
5e8aaf4e-0900-4f4f-bda4-fa7c461d643b	TOP FURNITURE & HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
d5987091-e431-4003-afd4-4eba35230673	UMMATHIS HOME STYLE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
8b914fae-0176-46fb-a307-c34403e48021	UPDATES TRADING LLP	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
ae8e4e27-d6e8-4744-a6f9-2b4dc5aaa0c9	WAFA MAHAL HOME APPLIANCES&ELECTRONICS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
86f6d3c5-3d92-4eb2-9e42-5822d00cd5b8	WE ELECTRON (Center Bill)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
8474112a-a0cd-4806-8e61-abaf6bc8a12c	WE ELECTRON PONNANI	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
949fe9f1-1d95-44bb-bd29-0183210f8da1	WHITE HYPERMARKET	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
c7490972-3523-46f2-bd80-34a41f07813b	ZAIN HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
b5918a2f-2036-44f5-a5be-3b14fa3ad81d	ABCD ELECTRONICS & HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
72db12da-e232-4a9f-83ae-7868e2e672e8	ANJALI ELECTRONICS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
885e0dd0-ce9d-4027-a5f8-7a88dbb98538	ARDH SAINIK CANTEEN	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
e2cd4cee-7ad1-4243-92ef-69ceb1aea411	ARIFA HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
911897a7-c327-42a5-8a19-f41c4f9a42fa	AVANI FURNITURES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
66b8b451-65d6-464f-aac0-78ac46b4f7b7	AYRIN ENTERPRISES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
e8064b7b-44ee-4d16-8d80-bbba052cc759	CHENKOTTA FURNITURE &HARDWARES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
d86368c6-811a-44fc-9c0a-58b2906483e5	Classic Home Appliance	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
36787750-89e6-4daa-8535-e0edf95c91e9	CLOUD MOBILES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
386609df-6876-4dcc-bc8f-531f0cd072d1	Dreams Home Appliances	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
662407c4-819c-4a9e-8e25-cd9abecae104	E1 Electronics,Home Appliances&Mobiles	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
b5a3bcac-62f5-43e2-8de5-13e5b4e2771e	HOMECENTRE APPLIANCES (PKD)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
cb491a54-c665-42b7-8758-4d01fccbe67c	KANKUNNATH HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
de4bd6e4-48b0-4801-b169-a93db1f578e3	KOTTARAM HYPER MARKET	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
0e9a5b61-7e9d-4b96-9878-82cc684f7734	MAAYON ELECTRONICS AND FURNITURE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
019715c5-b1a3-4a88-a39c-dbf3bc6a3807	MALABAR BAZAR	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
8ac2d235-a916-4a6a-afd2-75d2cdc0b849	MALABAR METRO	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
bcac8418-8969-4191-b4b0-31181d9380b4	MARHABA FURNITURE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
4424c5e3-44a3-4413-b916-1c8752a10bb9	Maria Home Appliance	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
4b937444-4d93-4e1c-bee6-b6d72553c3e9	MAXPLUS DIGITAL AND HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
425bf357-82e3-4610-9ae7-8ef861529346	Melco Eletrical Super Market	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
9969ef7a-cc90-459f-8b6e-72da3835d1e0	MELCO MYHOME	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
f5618c6c-78ad-4b9e-be9f-909b7d0c74c8	Melco the Electrical and Home World	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
1547a46f-d63b-4e94-99ee-7ff966a70619	MELCO TRADE CENTRE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
2d28d527-3b14-4b24-9b44-7ee55f056e40	MOHAN TV SALES & SERVICE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
1dc153db-ac06-4176-91e9-5c158be875f8	MUBARAQ  Elecronics&Home Appliances	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
a40e80c0-d5d2-4f39-9812-c9740153e295	MUBARAQ HOME SHOPPE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
1e139c27-357e-443d-b71e-b2a83f9c0b6d	MUBARAQ T.V Show Room	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
e57b1c2e-1f16-4025-85fb-c0ebfbdeb13f	Mubeena Furniture and Home Applinces	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
352503f6-534a-4ee0-a0f1-c0bd7ba50422	MULLAKKAL HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
e719cdd8-426e-4eee-be91-812c354af391	MULLAS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
6baf344a-1812-491f-9a6f-10053abe2bc9	NALAKATH AGENCIES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
9feb4181-c32e-4cd4-b91d-1dc7b24249cf	NANDHANA ELECTRONICS&HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
67363692-183e-453d-b621-7e2d8375846f	Neerkarakkat Agencies	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
4a5c1dd3-8929-4e6b-a0e2-1f2068e5928f	New India Home Appliances	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
6d2267c7-1d65-4fd0-9e15-53e2b7f16e05	NEW MALABAR HOME APPLIANCE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
2912c98b-4c72-4448-b983-76ccc4fd4c7e	PAK ENTERPRISES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
9a6988cc-e4ed-49ee-95fc-633d470bf61e	PH DIGITAL HUB	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
ee47cd51-ec0a-43d0-b4af-d258928f3859	PH MOBILES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
5c919c2e-8949-4a24-ad20-1a2374cb8501	P K ELECTRONICS&HOME NEEDS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
00273731-140f-45b4-a0fc-b5dbeb9296ee	P T M FURNITURE MANGODE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
eb8df156-540b-4bad-b9fc-5da98a74e20f	REGAL HOME APPLIANCES NEW	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
cfb6680a-ca41-4dee-97ee-6f941dd8fc45	RV HOME NEEDS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
39683a69-a1b9-43ef-a38c-5f7ee780278c	SREE LAKSHMI AGENCIES (PKD)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
b9280248-12b7-4777-b954-6d3c9ea57896	STAR VALUE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
b92a88b5-545d-43c3-a0b1-ebefc01397bf	TECNO LAND	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
13fbbbc6-c5ff-472a-8071-32334298c7e0	THEKKEKUTTU AGENCIES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
ee42dca1-fd90-4bf3-ab53-407d3d6d7dd2	VEMMARATHIL ELECTRONICS AND HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
52d2a626-6ad9-4d6b-84d0-0a6738a8158d	VERTEX MARKETING	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
42d2b7f8-b889-4257-af80-a0c69690bd31	Vrindavan Home Appliances	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
4aa4c2cb-554e-4fc8-a64b-65797ea8409a	Air Cool Shoppe	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
ebf23027-fae4-4fdd-87ce-0c04dbe53362	AMAZE ASSOCIATES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
9ed2aac9-720b-4a1f-87fd-4df257d3b508	ASSOCIATED COMPUTERS AND SECURITY SOLUTIONS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
531120bc-ddfc-4de9-be55-ff3ada1704f1	BEST HOME APPLIANCES (PDKL)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
3820f67f-5af1-483f-b1b6-ecaa7565fc88	CHOICE HOME COLLECTIONS (PTNTNI)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
20843723-3231-47b2-845d-492c3b4f3e1a	CK ASSOCIATES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
3ad3f6cf-2a9f-4bab-8f2d-c7f59c23a61a	COOL LINE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
b457cd00-1311-4063-929f-9ada9bdc1b42	EMINENT ELECTRICALS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
91a54a85-4949-413b-9529-65635e6762a5	FLASH ELECTRONICS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
f44ce545-7565-42d5-b2ac-05be7a356f1f	GRAND E MART	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
701808df-c64f-460d-a416-56154839818b	JUMBO ELECTRICAL TRADERS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
7715565d-29e5-4231-8f78-bfc10975312a	KK MOIDEEN AND SON	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
6bc1a59f-415e-49cc-8199-7e070d29bf97	KOHINOOR ELECTRONICS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
2dd95d9a-f493-4869-9912-d7a8e82bbf4b	LIFE KART (PTNGDI)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
b67af78d-759d-4cdd-b0c2-f8ba4d432cd8	MEPARAMBATH TRADERS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
0555f13e-dfa3-4b24-a1bf-dac9e3e31c06	MY MART DIGITAL ELECTRONICS & HOME APPLIANCES (KDV)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
c5643ff1-0af7-4166-a2a1-b213ce8f2972	NEW ZAHEER ELECTRONICS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
f327f63e-6583-42e9-9998-bd99060c080d	RAFEEQUE HOME CENTER	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
d795abb2-495b-43eb-b611-58ae894d7a51	REAL HOME CENTRE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
f6bf6f98-19d5-4860-9c2f-e3201749ef2d	SAI TRADERS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
8b71a912-7934-4d33-b2e3-d6be4724e726	TAJ HOME APPLAINCES & FURNITURE	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
22468c49-0327-4994-8c5c-62b4676b572e	TEEKAY HOMEAIDS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
cc18584f-bfaf-4599-827e-eb2d9ac4aa93	THAHIRA HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
7daf1ab6-becd-47fa-bcdf-8d7b92a5a11c	TRIVENI HOME APPLAINCES AGENCIES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
43b0f79f-97b4-49c8-bb9d-2c8c5e3d9f5d	UNITED BUSINESS CORPORATION (UBC)	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
9a801072-07a5-40b4-ad71-897bfb20eef3	VEE KEY HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
81eabae1-5d24-41d8-ab0a-ea083fcd931c	WE ELECTRON	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
86364ad7-8faa-42a1-877b-d015a31cc230	ZAHEER ELECTRONICS	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
42d55ea5-2d59-47f8-92e1-d5b0563bd6e8	Zaheer Enterprises	\N	\N	t	2026-10-08 15:56:28.770661+05:30	2026-10-08 15:56:28.770661+05:30
4ae69fc8-3263-43c8-b9a3-406e01e3c624	Akam Home Appliances&Mobiles(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
578105e8-a068-429f-8dca-aa3667bbb020	Amal Cool Air Conditioners(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
5c87318f-7f70-4269-9b8b-a16aba651fab	ASCO ENGINEERSCR(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
b7c3d268-3df5-4494-adbe-01e89d73b10e	ASSOCIATED COMPUTERS AND SECURITY SOLUTIONS (CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
8b5038ae-b6e8-4692-a3f6-62a158b61338	B S AGENCY(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
5c6fed18-d243-481a-8021-d105dcb9b751	DIGITAL MART (CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
a026839a-a89f-4c82-b44b-4ceb84ba6566	EVERCOOL REFRIGERATION &AIR CONDITION(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
5e351554-8dd4-47bb-8cad-ab4c16486c83	EXCEL APPLIANCES AND AIR CONDITIONS (CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
43aae77d-7a53-4af8-aef0-59b1839bc9ca	FRIDGE HOUSE(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
acff8543-d2a4-4766-9fb3-32130e694192	Friends Computers Home Appliances(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
786dfb76-f1c6-46f3-a8ae-0815aac1cb0f	G CONNECT(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
8668693e-0d33-4375-9d38-d7af56948f66	HOME CHOICE WANDOOR(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
c7ed8a02-d41d-4ee8-916d-5af094e42820	INFRA DIGITAL MART FACTORY OUTLET(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
0402117a-c498-44a0-bb80-76bdb510fc87	KALYANI E MART(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
0f1b58f9-5240-4d2c-8ee4-c3b40ea2ac47	KMK Electronics & Home Appliances( CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
8e93c528-f917-4de4-a59f-36936a9e9682	MARVEL APPIANCES (CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
8093664c-f282-4653-bf38-618524c3c521	NEW WAY CENTER (CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
db5f5a68-8825-46da-9415-b66659c22b8f	SHAJAHAN TV& FRIDGE HOUSE (CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
777f0154-88c9-4ca1-8d8f-5c2f6200d043	SIGMA ELECTRONICS & HOME BAZAR NLMBR(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
cf38443e-f73b-4376-9200-42348af2581b	STANTECH TRADING LLP(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
302d2015-1bad-4edf-953a-42aebf3778a7	SUPREME KOTTAKKAL (CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
559d76a2-3c74-4fac-b32f-de23a8a99dcb	TECHNO COOL(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
a6fec96f-f65b-491f-a3b2-be13c4d57191	TOP FURNITURE AND HOME APPLIANCES(CR)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
c9e455ae-1f65-4c84-a970-0700416ebd7d	Akam Home Appliances & Mobiles	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
5ee242de-1a74-41a4-8f9e-0453a428314d	Associated Computers and Security Solutions (Fmty)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
19372813-b1d3-4732-86df-f75ea2ccc1bb	AYISHA KUTTY	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
356bafe6-5f2e-4c9b-91d2-ee8d78c877f2	B & M 2 INTERNATIONAL INVESTMENT GROUP	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
0a9e71e2-8a8d-49a7-81d0-45690fd82f8e	Choice Home Selection (Chapanangadi)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
31ba9ab2-8716-47d3-9316-b960d8530ee7	CITY CHOICE CMD (F)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
47611cc8-c515-43d6-9f3b-38d9eea16fdb	CLASSICO HOME CENTRE(EDPL)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
58778c81-9ac8-4bda-bbc0-8aa1d0fcb488	Cool Land Tirur	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
8fe74a49-554b-481e-8c67-16e8d51df326	COOL MART HOME APPLIANCES (NEW)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
b9c2380d-e466-4651-90b6-b360e91bdb77	DIGITAL MART (AKD)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
f8cbcb35-4fb4-4c16-b324-99f951900b64	Friends Computers Home Appliances	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
2adea84b-cff6-4e89-a38b-1b95ce951bbf	Glockery Home Centre	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
e88d9d17-5b1a-4c65-a32a-47483f250ce5	Home Land Home Needs	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
0c503476-c680-4506-a19e-2c67ac2bc2ea	HOMEZO FURNITURE AND HOME APPLIANCES (FMTY)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
3f36d1f5-5a77-4c54-bd7a-5c977cbc4f2b	KATTIL HOME APPLIANCE(Pmbipdk)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
f1094384-a06e-4a3c-bbfc-e81d42dc2ecc	Kk Moidheen & Son	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
103536b0-a99f-4ad6-b4db-3dc49fb058b1	KMK Electronics & Home Appliances	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
065e0926-b0b9-4d38-b39b-93ce75b16f07	KRIPA HOME APPLIACES	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
2385c7ae-7531-41c0-b1ad-c575fbbc069f	Sana Home Bazar(Puthanathani)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
a24110aa-64db-4499-b3c5-2b4a9c5638da	Shajahan TV & Fridge House	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
f37ab5b3-8a3b-4643-bec2-6002a162bfe2	THAYYIL HOME CENTER	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
cc6e190b-b8f3-4403-a922-44b15c4117c1	Vee Key Home Appliaces	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
8b03eeb3-379c-41af-bfd4-e7255716218a	AERONEX COOLING SOLUTION(New)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
11aad461-54db-48e2-b0f4-4a3348bcac05	ASSOCIATED ELECTRONICS	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
f7a749f0-8f35-4205-bb99-963ae640ecf9	Benzy Home Makers Pvt Ltd	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
4502a854-719d-4b41-9db3-52e056eacb65	BigBuy Airconditioning Engineers	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
2689c076-a005-4c9a-b37c-a2db64880e0c	BigBuy Airconditioning Engineers (Vngara)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
562eae73-071a-40a9-a3be-a24482d0c907	Brand Store	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
e1498b8d-7149-4e6e-8afb-90276f96a16f	Breezy Homes	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
17235086-f57e-4c25-a4dc-1bc2b0bb7fe5	City Choice Chemad	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
f6686b31-f209-44a6-8c06-97604d2a96d6	CITY CHOICE VALANCHERY	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
cfaedd84-4b2e-4368-9a3a-bc38ac07ba4f	Continental Designer Pavers	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
5d7e3161-054a-446c-add2-6faed89bd0e2	COOL DAY AGENCIES	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
ac74d81c-b9a1-415e-9e98-81efcc3de4e7	CRYSTAL AGENCIES & HOME APPLIANCES (VGA)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
f0800d98-a466-4087-b7b1-9834b9f349fe	Day Night Air Conditioners	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
c3ac1578-1f5f-42df-97c2-2bf9627d8421	DIGI SOLAR SOLUTION	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
c39623ad-efe9-4aa1-b9ac-1117c920c6cc	DIGITAL MART (Kvnr) F	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
ac48bae2-6999-40ce-a6ac-d90fae619ea7	Evercool Refrigeration and Aircondition	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
18f6a4a7-b58d-4033-8465-dd3fce65f83e	Freeze World	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
c880574c-3949-4e22-9800-b58b3153e0a0	Hom Q Digital Electronics & Home	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
fe84dbc1-b3f8-4b06-9470-ccec92bda03c	Indian Electronics (Chelari)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
1dfce754-1156-44c1-818d-cea81d550353	KALPAKA ELECTRONICS & HOME BAZAR KDY	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
f72268cf-30c0-43d4-9470-447f6c2c01d5	KATTIL HOME APPLIANCE  PRMBIL(OG)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
8fbba9ca-3a88-4e1d-9fac-3a230b945d3b	KMK ELECTRONICS&HOME APPLIANCES(G)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
9dcb8f6a-193c-4bae-a44f-858a189c7875	LIFE HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
963649ef-f9c6-412a-93e8-bd81fd28f688	Malabar Enterprises	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
b6fe2adb-7fcb-4101-be42-c6ad33bfd11a	Master Cools Sales and Services	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
505c41a7-a6d0-408d-8aee-9b4a1386517f	Master Cools Sales & Services	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
b29913f1-3602-4879-ae33-fd5a75da8586	MEPARAMBATH TRADERS (NADUVATTOM)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
e23ff15c-056a-4257-a798-320a3dc80a05	M G AGENCIES	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
f97eaf29-6224-4579-a8f2-0789c6b208a3	Mia Cooling System	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
188c2a66-66dd-4b90-954c-0d011a3a9571	Muhammed Salih.P	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
c06cb53a-6a22-43cb-b3c6-bea163cfa9c7	NEW WAY CENTER	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
f5b85c11-3a3f-4e9b-a4d3-a68f52fdf569	Pazheri Cooling System	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
fb1b30d4-f29c-4a4c-9ee9-20253ea0f592	PRICE HVAC INTEGRATORS	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
93ae95c5-1dc6-49c1-a9bb-d5c8668108f0	Regal Home Appliances Koppam	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
653341e2-c005-4613-b1fe-8b276973f24e	SANA HOME BAZAR (Og)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
b3ee1119-3133-40ed-b6d1-ab248fdd7ebb	Sigma Electronics Gallary Edavanna	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
0b3a5d2b-37f2-4ad0-88a3-64342e96208c	SIGMA ELECTRONICS & HOME BAZAR NLMBR	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
39d64f4a-10ee-4db9-b913-02105a347abd	Sigma Electronics  Mnjri	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
5538dce5-f364-4cc6-a615-ab32c039b728	Stan Tech MEP Solution	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
94ad2022-bfc6-4a0f-a822-d214a8569d41	STANTECH TRADING LLP	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
5f248934-ff8a-4bca-ad48-c3d988db1678	TEEKAY  HOMEAIDS	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
d6f048b0-757a-46d6-bedd-2ac948581a83	ULTRA COOL(CLT)	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
a3ab4d6b-bc24-45e3-be8a-06c4ebf36a71	Valappil Home Style Pvt Ltd	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
5301bc9d-9158-4e80-9ace-94df0d4dc4d9	CRYSTAL HOME APPLIANCES	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
173a1f19-832b-42ed-ac32-6687c057e865	MALABAR PLUS	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
d37e8f4e-88d5-47ca-b238-191d95cf279c	MUBARAQ Electronics&Home Appliances	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
46f102a1-e4d7-45c0-9823-f9b08438314a	P K ELECTRONICS& HOME NEEDS	\N	\N	t	2026-10-08 15:56:49.875827+05:30	2026-10-08 15:56:49.875827+05:30
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.users (id, username, full_name, password_hash, role, is_active, created_at, updated_at) FROM stdin;
656f2005-9e50-4d61-9009-e9356e0a9c46	admin	System Administrator	$argon2id$v=19$m=65536,t=3,p=4$BqDUOuec09o7h/Cek9I6Rw$JV3hJkB8V1wsQLggAUuLLkxfPbkClgMLTLj/vbjRSMU	admin	t	2026-10-07 16:42:49.04992+05:30	2026-10-07 16:42:49.04992+05:30
1c32c290-0657-489b-adea-935fbe2d6659	staff	Warehouse Staff	$argon2id$v=19$m=65536,t=3,p=4$F4KwllLq3VsrZayVMmasFQ$C3i8v70G7yyzZC877CFZVjaRAys0YX3MvkbgYBJxqho	staff	f	2026-10-07 16:48:15.168029+05:30	2026-10-07 16:50:54.470285+05:30
433ebcc8-1377-4432-a88a-9b155a534784	shihab	Shihab	$argon2id$v=19$m=65536,t=3,p=4$0BpjzHmPcc7ZG6P0/l/LeQ$p/XXUK7pTZ809yCCIP3cYqRaioVWIhz09VKI+b9efug	staff	t	2026-10-07 16:51:25.668739+05:30	2026-10-08 13:15:02.517058+05:30
\.


--
-- Name: alembic_version alembic_version_pkc; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alembic_version
    ADD CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: devices devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_pkey PRIMARY KEY (id);


--
-- Name: inward_batches inward_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inward_batches
    ADD CONSTRAINT inward_batches_pkey PRIMARY KEY (id);


--
-- Name: inward_lines inward_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inward_lines
    ADD CONSTRAINT inward_lines_pkey PRIMARY KEY (id);


--
-- Name: outward_batches outward_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outward_batches
    ADD CONSTRAINT outward_batches_pkey PRIMARY KEY (id);


--
-- Name: outward_lines outward_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outward_lines
    ADD CONSTRAINT outward_lines_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: returns returns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_pkey PRIMARY KEY (id);


--
-- Name: serial_history serial_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.serial_history
    ADD CONSTRAINT serial_history_pkey PRIMARY KEY (id);


--
-- Name: serial_numbers serial_numbers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.serial_numbers
    ADD CONSTRAINT serial_numbers_pkey PRIMARY KEY (id);


--
-- Name: shops shops_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shops
    ADD CONSTRAINT shops_pkey PRIMARY KEY (id);


--
-- Name: inward_lines uq_inward_lines_batch_serial; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inward_lines
    ADD CONSTRAINT uq_inward_lines_batch_serial UNIQUE (batch_id, serial_number_id);


--
-- Name: outward_lines uq_outward_lines_batch_serial; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outward_lines
    ADD CONSTRAINT uq_outward_lines_batch_serial UNIQUE (batch_id, serial_text);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: ix_audit_log_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_audit_log_action ON public.audit_log USING btree (action);


--
-- Name: ix_audit_log_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_audit_log_created_at ON public.audit_log USING btree (created_at);


--
-- Name: ix_audit_log_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_audit_log_entity_id ON public.audit_log USING btree (entity_id);


--
-- Name: ix_audit_log_entity_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_audit_log_entity_type ON public.audit_log USING btree (entity_type);


--
-- Name: ix_audit_log_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_audit_log_user_id ON public.audit_log USING btree (user_id);


--
-- Name: ix_categories_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_categories_name ON public.categories USING btree (name);


--
-- Name: ix_devices_device_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_devices_device_uid ON public.devices USING btree (device_uid);


--
-- Name: ix_inward_batches_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inward_batches_product_id ON public.inward_batches USING btree (product_id);


--
-- Name: ix_inward_batches_transaction_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inward_batches_transaction_date ON public.inward_batches USING btree (transaction_date);


--
-- Name: ix_inward_lines_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inward_lines_batch_id ON public.inward_lines USING btree (batch_id);


--
-- Name: ix_inward_lines_serial_number_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inward_lines_serial_number_id ON public.inward_lines USING btree (serial_number_id);


--
-- Name: ix_outward_batches_bill_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_outward_batches_bill_number ON public.outward_batches USING btree (bill_number);


--
-- Name: ix_outward_batches_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_outward_batches_product_id ON public.outward_batches USING btree (product_id);


--
-- Name: ix_outward_batches_shop_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_outward_batches_shop_id ON public.outward_batches USING btree (shop_id);


--
-- Name: ix_outward_batches_transaction_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_outward_batches_transaction_date ON public.outward_batches USING btree (transaction_date);


--
-- Name: ix_outward_lines_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_outward_lines_batch_id ON public.outward_lines USING btree (batch_id);


--
-- Name: ix_outward_lines_is_flagged; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_outward_lines_is_flagged ON public.outward_lines USING btree (is_flagged_for_review);


--
-- Name: ix_outward_lines_is_matched; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_outward_lines_is_matched ON public.outward_lines USING btree (is_matched);


--
-- Name: ix_outward_lines_serial_number_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_outward_lines_serial_number_id ON public.outward_lines USING btree (serial_number_id);


--
-- Name: ix_outward_lines_serial_text; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_outward_lines_serial_text ON public.outward_lines USING btree (serial_text);


--
-- Name: ix_outward_lines_shop_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_outward_lines_shop_id ON public.outward_lines USING btree (shop_id);


--
-- Name: ix_outward_lines_transaction_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_outward_lines_transaction_date ON public.outward_lines USING btree (transaction_date);


--
-- Name: ix_products_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_products_category_id ON public.products USING btree (category_id);


--
-- Name: ix_products_sku; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_products_sku ON public.products USING btree (sku);


--
-- Name: ix_returns_return_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_returns_return_date ON public.returns USING btree (return_date);


--
-- Name: ix_returns_serial_number_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_returns_serial_number_id ON public.returns USING btree (serial_number_id);


--
-- Name: ix_returns_serial_text; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_returns_serial_text ON public.returns USING btree (serial_text);


--
-- Name: ix_returns_shop_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_returns_shop_id ON public.returns USING btree (shop_id);


--
-- Name: ix_serial_history_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_serial_history_action ON public.serial_history USING btree (action);


--
-- Name: ix_serial_history_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_serial_history_created_at ON public.serial_history USING btree (created_at);


--
-- Name: ix_serial_history_serial_number_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_serial_history_serial_number_id ON public.serial_history USING btree (serial_number_id);


--
-- Name: ix_serial_history_serial_text; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_serial_history_serial_text ON public.serial_history USING btree (serial_text);


--
-- Name: ix_serial_history_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_serial_history_user_id ON public.serial_history USING btree (user_id);


--
-- Name: ix_serial_numbers_last_shop_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_serial_numbers_last_shop_id ON public.serial_numbers USING btree (last_shop_id);


--
-- Name: ix_serial_numbers_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_serial_numbers_product_id ON public.serial_numbers USING btree (product_id);


--
-- Name: ix_serial_numbers_serial_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_serial_numbers_serial_number ON public.serial_numbers USING btree (serial_number);


--
-- Name: ix_serial_numbers_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_serial_numbers_status ON public.serial_numbers USING btree (status);


--
-- Name: ix_users_username; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_users_username ON public.users USING btree (username);


--
-- Name: audit_log audit_log_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE SET NULL;


--
-- Name: audit_log audit_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: devices devices_approved_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_approved_by_id_fkey FOREIGN KEY (approved_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: inward_batches inward_batches_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inward_batches
    ADD CONSTRAINT inward_batches_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE SET NULL;


--
-- Name: inward_batches inward_batches_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inward_batches
    ADD CONSTRAINT inward_batches_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;


--
-- Name: inward_batches inward_batches_received_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inward_batches
    ADD CONSTRAINT inward_batches_received_by_user_id_fkey FOREIGN KEY (received_by_user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: inward_lines inward_lines_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inward_lines
    ADD CONSTRAINT inward_lines_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.inward_batches(id) ON DELETE CASCADE;


--
-- Name: inward_lines inward_lines_serial_number_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inward_lines
    ADD CONSTRAINT inward_lines_serial_number_id_fkey FOREIGN KEY (serial_number_id) REFERENCES public.serial_numbers(id) ON DELETE RESTRICT;


--
-- Name: outward_batches outward_batches_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outward_batches
    ADD CONSTRAINT outward_batches_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE SET NULL;


--
-- Name: outward_batches outward_batches_dispatched_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outward_batches
    ADD CONSTRAINT outward_batches_dispatched_by_user_id_fkey FOREIGN KEY (dispatched_by_user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: outward_batches outward_batches_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outward_batches
    ADD CONSTRAINT outward_batches_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;


--
-- Name: outward_batches outward_batches_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outward_batches
    ADD CONSTRAINT outward_batches_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shops(id) ON DELETE RESTRICT;


--
-- Name: outward_lines outward_lines_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outward_lines
    ADD CONSTRAINT outward_lines_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.outward_batches(id) ON DELETE CASCADE;


--
-- Name: outward_lines outward_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outward_lines
    ADD CONSTRAINT outward_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;


--
-- Name: outward_lines outward_lines_serial_number_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outward_lines
    ADD CONSTRAINT outward_lines_serial_number_id_fkey FOREIGN KEY (serial_number_id) REFERENCES public.serial_numbers(id) ON DELETE SET NULL;


--
-- Name: outward_lines outward_lines_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outward_lines
    ADD CONSTRAINT outward_lines_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shops(id) ON DELETE RESTRICT;


--
-- Name: products products_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE RESTRICT;


--
-- Name: returns returns_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE SET NULL;


--
-- Name: returns returns_inspected_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_inspected_by_user_id_fkey FOREIGN KEY (inspected_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: returns returns_outward_line_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_outward_line_id_fkey FOREIGN KEY (outward_line_id) REFERENCES public.outward_lines(id) ON DELETE SET NULL;


--
-- Name: returns returns_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;


--
-- Name: returns returns_received_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_received_by_user_id_fkey FOREIGN KEY (received_by_user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: returns returns_serial_number_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_serial_number_id_fkey FOREIGN KEY (serial_number_id) REFERENCES public.serial_numbers(id) ON DELETE SET NULL;


--
-- Name: returns returns_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shops(id) ON DELETE RESTRICT;


--
-- Name: serial_history serial_history_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.serial_history
    ADD CONSTRAINT serial_history_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE SET NULL;


--
-- Name: serial_history serial_history_inward_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.serial_history
    ADD CONSTRAINT serial_history_inward_batch_id_fkey FOREIGN KEY (inward_batch_id) REFERENCES public.inward_batches(id) ON DELETE SET NULL;


--
-- Name: serial_history serial_history_outward_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.serial_history
    ADD CONSTRAINT serial_history_outward_batch_id_fkey FOREIGN KEY (outward_batch_id) REFERENCES public.outward_batches(id) ON DELETE SET NULL;


--
-- Name: serial_history serial_history_return_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.serial_history
    ADD CONSTRAINT serial_history_return_id_fkey FOREIGN KEY (return_id) REFERENCES public.returns(id) ON DELETE SET NULL;


--
-- Name: serial_history serial_history_serial_number_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.serial_history
    ADD CONSTRAINT serial_history_serial_number_id_fkey FOREIGN KEY (serial_number_id) REFERENCES public.serial_numbers(id) ON DELETE SET NULL;


--
-- Name: serial_history serial_history_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.serial_history
    ADD CONSTRAINT serial_history_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shops(id) ON DELETE SET NULL;


--
-- Name: serial_history serial_history_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.serial_history
    ADD CONSTRAINT serial_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: serial_numbers serial_numbers_last_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.serial_numbers
    ADD CONSTRAINT serial_numbers_last_shop_id_fkey FOREIGN KEY (last_shop_id) REFERENCES public.shops(id) ON DELETE SET NULL;


--
-- Name: serial_numbers serial_numbers_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.serial_numbers
    ADD CONSTRAINT serial_numbers_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

\unrestrict 14ds11YeyEKDpymXFeyBlN14kFw2aDhAmSOVquekVXUVlSkAql2R3nL6N6WIKlo

