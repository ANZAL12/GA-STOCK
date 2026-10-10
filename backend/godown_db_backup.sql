--
-- PostgreSQL database dump
--


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

INSERT INTO public.alembic_version (version_num) VALUES ('0004');


--
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('82b803ac-d0e3-4dde-b2c0-003f5d065e4f', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'EXCEL_SHOPS_IMPORTED', 'shop', 'bulk', '{"column_used": "Particulars", "created_count": 132, "created_shops": ["Akam Home Appliances&Mobiles(CR)", "Amal Cool Air Conditioners(CR)", "ASCO ENGINEERSCR(CR)", "ASSOCIATED COMPUTERS AND SECURITY SOLUTIONS (CR)", "B S AGENCY(CR)", "DIGITAL MART (CR)", "EVERCOOL REFRIGERATION &AIR CONDITION(CR)", "EXCEL APPLIANCES AND AIR CONDITIONS (CR)", "FRIDGE HOUSE(CR)", "Friends Computers Home Appliances(CR)", "G CONNECT(CR)", "HOME CHOICE WANDOOR(CR)", "INFRA DIGITAL MART FACTORY OUTLET(CR)", "KALYANI E MART(CR)", "KMK Electronics & Home Appliances( CR)", "MARVEL APPIANCES (CR)", "NEW WAY CENTER (CR)", "PRAKASH TRADERS", "SHAJAHAN TV& FRIDGE HOUSE (CR)", "SIGMA ELECTRONICS & HOME BAZAR NLMBR(CR)", "STANTECH TRADING LLP(CR)", "SUPREME KOTTAKKAL (CR)", "TECHNO COOL(CR)", "TOP FURNITURE AND HOME APPLIANCES(CR)", "AIWA COLLECTION & DISTRIBUTIONS", "Akam Home Appliances & Mobiles", "Associated Computers and Security Solutions (Fmty)", "AYISHA KUTTY", "B & M 2 INTERNATIONAL INVESTMENT GROUP", "Choice Home Selection (Chapanangadi)", "CITY CHOICE CMD (F)", "CLASSICO HOME CENTRE(EDPL)", "Classico Home Centre (Vlry)", "Cool Land Tirur", "COOL MART HOME APPLIANCES (NEW)", "Digital Mart", "DIGITAL MART (AKD)", "Digital Mart (Kvnr)", "Dream Digital", "Eminent Electricals", "E WORLD Home Appliances(New)", "Friends Computers Home Appliances", "GK ENTERPRISES", "Glockery Home Centre", "Home Land Home Needs", "HOMEZO FURNITURE AND HOME APPLIANCES (FMTY)", "Infra Digital Mart Factory Out Let", "KATTIL HOME APPLIANCE(Pmbipdk)", "KATTIPARUTHY HOME GUIDE", "Kk Moidheen & Son"]}', NULL, '2026-10-08 12:51:00.963244+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('1fc17411-dd15-4160-a2c5-64542b90139a', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'DEVICE_APPROVED', 'device', '14a77e6e-6251-4bf8-b839-519260e205ae', '{"label": "Android Godown Scanner", "device_uid": "0300630b-cb12-4010-af1e-1c414df029f1"}', NULL, '2026-10-08 13:14:39.154519+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('559e2926-542c-4218-9297-3c204177b056', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'USER_UPDATED', 'user', '433ebcc8-1377-4432-a88a-9b155a534784', '{"role": "staff", "username": "shihab", "is_active": true}', NULL, '2026-10-08 13:15:02.517058+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('277bb834-ac60-470b-8099-c79e580ed0f2', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'EXCEL_SHOPS_IMPORTED', 'shop', 'bulk', '{"column_used": "Particulars", "created_count": 188, "created_shops": ["ANAS HOME APPLIANCES", "DR.DOOR", "EVERCOOL ENTERPRISES", "FRIENDS COMPUTERS HOME APPLAINCES & SECURITY SYSTEM", "GODS OWN", "GRAND HOME APPLIANCE", "HELAN DIGITAL MART", "KADOOR ELECTRONICS", "KALPAKA ELECTRONICS & HOME BAZAR", "Kannankandy Fridge centre", "KASIM KUMMALI ADV", "MAB TECH EQUIPMENT PRIVATE LIMITED(New)", "Mandhi Palce", "MANSOOR PATTAMBI", "Mr YESHUDAS", "MUJEEB ARIMBRA", "NESTO HYPER MARKET (CLT)", "NEW WHITE HOME", "OMEGA AGENCIES", "PV STORE", "PV STORE EKKAPPARAMBU", "REAL AGENCY", "RETAIL BILL", "RIYAS ROK", "SHAMEER PANDI", "SIGMA ELECTRONICS MANJERI", "SMART HOME APPLIANCES", "S.P TRADERS", "VAVA FURNITURE AND HOME APPLIANCES(New)", "VK GROUP", "AKAM  HOME APPLIANCES & MOBILES", "A K M STORE", "ASHIKH ELECTRONIC AND HOME APPLIANCES", "Brand House Agencies", "BROTHERS HOME APPLAINES & FURNITURE", "BUDGET FURNITURE & HOME APPLIANCES", "BUDGET FURNITURE & HOME APPLIANCES (PNKD)", "CHOICE HOME SERVICES (Mtvlr)", "Cool India Home Needs & Appliances", "Cool Makers", "ELECTRO WORLD FRIDGE HOUSE", "ELITE METALS & HOME NEEDS  MJRY", "E MAX DIGITAL", "FAMILY HOMELAND ELECTRICALS & SANITARY", "FAMILY METALS & FURNITURE", "FOCUS FURNITURE & ELECTRONICS", "FRIDGE HOUSE", "HAPPY HOME", "Happy Home Hardware & Electricals", "HI MART HYPERMARKET"]}', NULL, '2026-10-08 15:53:10.20424+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('11d8bbfa-cbef-4387-8a1d-f672b03fdc02', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'SHOP_PERMANENTLY_DELETED', 'shop', '2719f84c-c499-4704-b8f5-f3f687d0dc88', '{"city": null, "name": "A K M STORE"}', NULL, '2026-10-08 15:53:24.982194+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('5511b4a2-7179-4190-b870-d1ed627d9dbf', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'SHOP_PERMANENTLY_DELETED', 'shop', 'c5858f44-0ef4-4ce0-8db3-7a3f94ed3b41', '{"city": null, "name": "ABCD ELECTRONICS & HOME APPLIANCES"}', NULL, '2026-10-08 15:53:34.981684+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('ac80f7c2-fb72-4782-a076-bf19aac90cd2', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'EXCEL_SHOPS_IMPORTED', 'shop', 'bulk', '{"column_used": "Particulars", "created_count": 228, "created_shops": ["ANAS HOME APPLIANCES", "BENZY HOSPITALS PRIVATE LIMITED", "DR.DOOR", "EVERCOOL ENTERPRISES", "FRIENDS COMPUTERS HOME APPLAINCES & SECURITY SYSTEM", "GODS OWN", "GRAND HOME APPLIANCE", "HAYATH MEDICAL CENTRE", "HELAN DIGITAL MART", "KADOOR ELECTRONICS", "KALPAKA ELECTRONICS (FRK)", "KALPAKA ELECTRONICS & HOME BAZAR", "Kalpaka Electronics & Home Bazar Mlp", "Kannankandy Fridge centre", "KASIM KUMMALI ADV", "KERALA FLIGHT ACADEMY PRIVATE LIMITED", "MAB TECH EQUIPMENT PRIVATE LIMITED(New)", "Mandhi Palce", "MANSOOR PATTAMBI", "MERRY SOUL ENTERPRISE", "Mr YESHUDAS", "MUJEEB ARIMBRA", "NESTO HYPER MARKET (CLT)", "NEW TECH COOLING SOLUTIONS", "NEW WHITE HOME", "OMEGA AGENCIES", "PRAKASH TRADERS", "PV STORE", "PV STORE EKKAPPARAMBU", "REAL AGENCY", "RETAIL BILL", "RIYAS ROK", "SHAMEER PANDI", "SIGMA ELECTRONICS MANJERI", "SMART HOME APPLIANCES", "S.P TRADERS", "VAVA FURNITURE AND HOME APPLIANCES(New)", "VK GROUP", "AKAM  HOME APPLIANCES & MOBILES", "A K M STORE", "ASHIKH ELECTRONIC AND HOME APPLIANCES", "Brand House Agencies", "BROTHERS HOME APPLAINES & FURNITURE", "BUDGET FURNITURE & HOME APPLIANCES", "BUDGET FURNITURE & HOME APPLIANCES (PNKD)", "CHOICE HOME SERVICES (Mtvlr)", "Cool India Home Needs & Appliances", "Cool Makers", "DIGITAL MART", "Digital Mart (Kvnr)"]}', NULL, '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('3d8c0965-bdc3-463d-85ce-1d8b05acff39', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'EXCEL_SHOPS_IMPORTED', 'shop', 'bulk', '{"column_used": "Particulars", "created_count": 92, "created_shops": ["Akam Home Appliances&Mobiles(CR)", "Amal Cool Air Conditioners(CR)", "ASCO ENGINEERSCR(CR)", "ASSOCIATED COMPUTERS AND SECURITY SOLUTIONS (CR)", "B S AGENCY(CR)", "DIGITAL MART (CR)", "EVERCOOL REFRIGERATION &AIR CONDITION(CR)", "EXCEL APPLIANCES AND AIR CONDITIONS (CR)", "FRIDGE HOUSE(CR)", "Friends Computers Home Appliances(CR)", "G CONNECT(CR)", "HOME CHOICE WANDOOR(CR)", "INFRA DIGITAL MART FACTORY OUTLET(CR)", "KALYANI E MART(CR)", "KMK Electronics & Home Appliances( CR)", "MARVEL APPIANCES (CR)", "NEW WAY CENTER (CR)", "SHAJAHAN TV& FRIDGE HOUSE (CR)", "SIGMA ELECTRONICS & HOME BAZAR NLMBR(CR)", "STANTECH TRADING LLP(CR)", "SUPREME KOTTAKKAL (CR)", "TECHNO COOL(CR)", "TOP FURNITURE AND HOME APPLIANCES(CR)", "Akam Home Appliances & Mobiles", "Associated Computers and Security Solutions (Fmty)", "AYISHA KUTTY", "B & M 2 INTERNATIONAL INVESTMENT GROUP", "Choice Home Selection (Chapanangadi)", "CITY CHOICE CMD (F)", "CLASSICO HOME CENTRE(EDPL)", "Cool Land Tirur", "COOL MART HOME APPLIANCES (NEW)", "DIGITAL MART (AKD)", "Friends Computers Home Appliances", "Glockery Home Centre", "Home Land Home Needs", "HOMEZO FURNITURE AND HOME APPLIANCES (FMTY)", "KATTIL HOME APPLIANCE(Pmbipdk)", "Kk Moidheen & Son", "KMK Electronics & Home Appliances", "KRIPA HOME APPLIACES", "Sana Home Bazar(Puthanathani)", "Shajahan TV & Fridge House", "THAYYIL HOME CENTER", "Vee Key Home Appliaces", "AERONEX COOLING SOLUTION(New)", "ASSOCIATED ELECTRONICS", "Benzy Home Makers Pvt Ltd", "BigBuy Airconditioning Engineers", "BigBuy Airconditioning Engineers (Vngara)"]}', NULL, '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('9418b640-e805-4a73-8e57-efdd368c710d', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'CATEGORY_CREATED', 'category', 'a61627a9-d0a7-49b8-af5f-56c872026561', '{"name": "AC", "has_dual_serial": true}', NULL, '2026-10-08 16:00:02.724115+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('ea82716c-d442-4114-90a9-a0597240fcdf', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'CATEGORY_CREATED', 'category', 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', '{"name": "WASHING MACHINE", "has_dual_serial": false}', NULL, '2026-10-08 16:02:46.527857+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('be88e31b-d064-491a-9d80-c81b4e039dd2', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'CATEGORY_CREATED', 'category', '3866bb27-b9b4-40c1-99b8-2aed06198a18', '{"name": "REFERIGERATOR", "has_dual_serial": false}', NULL, '2026-10-08 16:03:02.90933+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('ddd2837f-54a3-483b-bf74-5ce455e002e6', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'CATEGORY_CREATED', 'category', '043d664f-f89e-4187-99f0-ff9bceb2575c', '{"name": "TV", "has_dual_serial": false}', NULL, '2026-10-08 16:03:49.907974+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('b855a7b0-dc44-4308-9ab5-84f2d896c58d', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'DEVICE_APPROVED', 'device', 'e5621cd5-aaa0-40f3-9e5f-6c02b89d0d0a', '{"label": "Android Godown Scanner", "device_uid": "16b82feb-9760-4ded-a520-6d92be809377"}', NULL, '2026-10-08 16:39:58.394775+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('38fabcd9-a46b-4d88-b9c8-e399ad292a2d', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', 'b3c1b461-b0f1-4c8e-9dbe-8dd56d2e6a95', '{"name": "ROCKWELL GFR 450 DDUC-5S", "brand": "ROCKWELL", "model": "GFR 450 DDUC-5S", "opening_stock_qty": 0}', NULL, '2026-10-08 16:59:51.604125+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('ba9bc558-78d3-4aa3-9b35-227771c0b5d8', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '79506c87-6018-4ea5-9b28-6462f32ade86', '{"name": "ROCKWELL GFR 550 DDUCSS5S", "brand": "ROCKWELL", "model": "GFR 550 DDUCSS5S", "opening_stock_qty": 0}', NULL, '2026-10-08 17:00:55.19106+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('efe772ac-e2b7-4a1e-af87-d5a03338f84c', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '0cc42ac9-3e11-4609-9075-fbc5e90bf39c', '{"name": "ROCKWELL GFR 910 UC5S", "brand": "ROCKWELL", "model": "GFR 910 UC5S", "opening_stock_qty": 0}', NULL, '2026-10-08 17:01:52.374719+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('36c673eb-eaae-4a51-8fba-a7c38cce1c97', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'CATEGORY_CREATED', 'category', '5d3395d9-808e-4fff-815c-a0facdf8bbdb', '{"name": "FREEZER", "has_dual_serial": false}', NULL, '2026-10-08 16:58:41.867432+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('b3c4b7af-ee12-42d0-840b-0eef0cba1646', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_OPENING_STOCK_EDITED', 'product', '7f4ac78e-a27b-428d-8d41-09e90e30beb2', '{"diff": 2, "name": "ROCKWELL GFR1210F", "has_had_inward": false, "new_current_stock": 2, "new_opening_stock": 2, "old_current_stock": 0, "old_opening_stock": 0}', NULL, '2026-10-08 16:59:10.530479+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('8dbe0d27-56c1-46ee-afb1-f9a213623359', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_UPDATED', 'product', '7f4ac78e-a27b-428d-8d41-09e90e30beb2', '{"name": "ROCKWELL GFR1210F", "is_active": true}', NULL, '2026-10-08 16:59:10.530479+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('0d471562-94cf-49f8-b7b7-a436c7985106', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '7f4ac78e-a27b-428d-8d41-09e90e30beb2', '{"name": "ROCKWELL GFR1210F", "brand": "ROCKWELL", "model": "GFR1210F", "opening_stock_qty": 0}', NULL, '2026-10-08 16:59:02.587912+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('e4e9449a-cf7e-422e-813d-f48ba5918344', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_OPENING_STOCK_EDITED', 'product', '7f4ac78e-a27b-428d-8d41-09e90e30beb2', '{"diff": -2, "name": "ROCKWELL GFR1210F", "has_had_inward": false, "new_current_stock": 0, "new_opening_stock": 0, "old_current_stock": 2, "old_opening_stock": 2}', NULL, '2026-10-08 16:59:17.376888+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('f04f56f8-7818-479a-a132-d9d5e275ad6d', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_UPDATED', 'product', '7f4ac78e-a27b-428d-8d41-09e90e30beb2', '{"name": "ROCKWELL GFR1210F", "is_active": true}', NULL, '2026-10-08 16:59:17.376888+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('8d07dc94-2199-4918-9c3d-53ff07ae2590', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '434b9a12-b1bf-4628-92eb-d8c334d06686', '{"name": "ROCKWELL GFR 550 DDUC5S", "brand": "ROCKWELL", "model": "GFR 550 DDUC5S", "opening_stock_qty": 0}', NULL, '2026-10-08 17:00:26.890128+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('712c8015-9609-4106-bf7e-b868767e2301', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '0fd5dc56-f051-441c-a32f-031aa85c4438', '{"name": "ROCKWELL GFR 910 UC5S", "brand": "ROCKWELL", "model": "GFR 910 UC5S", "opening_stock_qty": 0}', NULL, '2026-10-08 17:01:12.983859+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('5ba34572-3759-487a-b539-3581f8cd0a4e', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '4f7e752a-a900-4279-a7f3-bdd59c7e4887', '{"name": "ROCKWELL ROCKWELL MB-100", "brand": "ROCKWELL", "model": "ROCKWELL MB-100", "opening_stock_qty": 0}', NULL, '2026-10-08 17:02:27.009787+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('1a1acd84-ce02-4e41-9aff-554a97f0865c', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '67a2e9f1-233d-4ea7-a576-5fc33861d833', '{"name": "ROCKWELL RVC 1100", "brand": "ROCKWELL", "model": "RVC 1100", "opening_stock_qty": 0}', NULL, '2026-10-08 17:02:45.326261+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('146f1378-83fc-4585-88af-45c76fdf172a', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', 'acb37210-eb8a-4759-b4f0-fb46e2a90e7a', '{"name": "ROCKWELL RVC 400", "brand": "ROCKWELL", "model": "RVC 400", "opening_stock_qty": 0}', NULL, '2026-10-08 17:03:13.350828+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('5a0b08a7-8e4a-464a-aa3d-45eacb0cd763', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '72aa311b-e0c8-4a6f-8d9e-80c9c5cad30f', '{"name": "ROCKWELL RVC 550", "brand": "ROCKWELL", "model": "RVC 550", "opening_stock_qty": 0}', NULL, '2026-10-08 17:03:59.677214+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('2cdfa137-b69d-4717-b19b-de1de34e7f0c', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '8d2b048f-fb53-476e-82e4-caba8d509b76', '{"name": "ROCKWELL RVC 700", "brand": "ROCKWELL", "model": "RVC 700", "opening_stock_qty": 0}', NULL, '2026-10-08 17:04:13.25429+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('09cf18ea-f8f0-4ce2-b745-5dfd2c8168b7', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '2a6fb377-44d5-4b58-9882-6a4e69839104', '{"name": "ROCKWELL SFR 250 SDU-4S", "brand": "ROCKWELL", "model": "SFR 250 SDU-4S", "opening_stock_qty": 0}', NULL, '2026-10-08 17:04:40.124677+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('82ddb739-5a02-42ff-9fdb-fdd988b17f3b', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', 'e005dfbd-c056-416f-8fb9-74067e0a4659', '{"name": "ROCKWELL SFR 350 DDU5S", "brand": "ROCKWELL", "model": "SFR 350 DDU5S", "opening_stock_qty": 0}', NULL, '2026-10-08 17:05:34.143567+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('63081695-25f8-45f2-9593-aab59941ccc6', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '98c6d742-2bce-4e95-9ba6-daa72bebd5f0', '{"name": "ROCKWELL SFR 350GTS LED", "brand": "ROCKWELL", "model": "SFR 350GTS LED", "opening_stock_qty": 0}', NULL, '2026-10-08 17:06:10.005308+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('4b9e2d22-3ac4-4a45-bff4-71e7f9edce41', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '7449ebcc-8d69-42c3-8df2-d20a0c37a96c', '{"name": "ROCKWELL SFR 450 DDU-5S", "brand": "ROCKWELL", "model": "SFR 450 DDU-5S", "opening_stock_qty": 0}', NULL, '2026-10-08 17:06:24.958425+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('e9d04f37-b6a5-4939-986a-e045f2193f7d', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '26eca82c-bd82-4819-a3c9-cab776834bfb', '{"name": "ROCKWELL SFR 450 GTS LED", "brand": "ROCKWELL", "model": "SFR 450 GTS LED", "opening_stock_qty": 0}', NULL, '2026-10-08 17:06:49.050572+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('9ed82d75-8d9d-40fb-833e-4795a9a3f662', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '5dfb33bf-2c0a-40c2-a340-448ad9c825d5', '{"name": "ROCKWELL SFR 550 DDU5S", "brand": "ROCKWELL", "model": "SFR 550 DDU5S", "opening_stock_qty": 0}', NULL, '2026-10-08 17:07:04.86483+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('87ed4f38-a041-4d3a-b10f-6dddbc7e1c1c', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', 'bacc9a8e-8ce2-455f-9166-809aba107dfa', '{"name": "ROCKWELL SFR 750 TDU5S", "brand": "ROCKWELL", "model": "SFR 750 TDU5S", "opening_stock_qty": 0}', NULL, '2026-10-08 17:08:46.137962+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('31c70046-f9c2-413e-ba14-8d0fda87a16a', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_DEACTIVATED', 'product', '0fd5dc56-f051-441c-a32f-031aa85c4438', '{"name": "ROCKWELL GFR 910 UC5S"}', NULL, '2026-10-08 17:12:18.722915+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('fcf17444-83a0-467c-8423-5e8135a3cb48', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', 'b98ff282-df28-4a8b-962f-0da93398777c', '{"name": "GENERAL 12CGWA-B 1.0T INV AC", "brand": "GENERAL", "model": "12CGWA-B 1.0T INV AC", "opening_stock_qty": 0}', NULL, '2026-10-08 17:13:23.323547+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('b0069967-9dc3-4603-8c6f-99ea06c4cb6e', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '3f5872a1-df35-4bf7-85b4-22cc53085f79', '{"name": "GENERAL ASGA 18 BMAA-B 1.5T Split Ac", "brand": "GENERAL", "model": "ASGA 18 BMAA-B 1.5T Split Ac", "opening_stock_qty": 0}', NULL, '2026-10-08 17:13:51.763891+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('a9c911df-1f40-48c2-b633-33fdb8d731f2', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '43fd84b0-ee86-4411-9d4c-0a0ac31959af', '{"name": "GENERAL ASGA18BUTA-B", "brand": "GENERAL", "model": "ASGA18BUTA-B", "opening_stock_qty": 0}', NULL, '2026-10-08 17:14:09.64954+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('f2934e73-7c76-4353-a067-33790833d994', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '8811c429-0cf7-477f-ada4-18fdaa1beee1', '{"name": "GENERAL ASGA18BUTA-B", "brand": "GENERAL", "model": "ASGA18BUTA-B", "opening_stock_qty": 0}', NULL, '2026-10-08 17:14:29.48848+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('936b629b-2408-486e-bb06-287e57bf9c55', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_UPDATED', 'product', '43fd84b0-ee86-4411-9d4c-0a0ac31959af', '{"name": "GENERAL ASGA 24 BMAA-B 2.0T Split Ac", "is_active": true}', NULL, '2026-10-08 17:14:46.283152+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('36a99d9d-4fb3-49d4-a080-becfc97ce8e6', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '09582965-46f7-4019-bba0-7161ec1cfeb3', '{"name": "GENERAL ASGA24BUTA-B 2T", "brand": "GENERAL", "model": "ASGA24BUTA-B 2T", "opening_stock_qty": 0}', NULL, '2026-10-08 17:15:02.38574+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('742ab445-1399-4738-aeb7-3c83f198ce19', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '03aca04a-fcf1-4708-bbac-074130fc2c0f', '{"name": "GENERAL ASGG 12CGAB-B 1T INV AC", "brand": "GENERAL", "model": "ASGG 12CGAB-B 1T INV AC", "opening_stock_qty": 0}', NULL, '2026-10-08 17:15:32.1243+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('5265442b-0a71-4ec7-bd0f-e752e2281121', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '2466d044-b519-4a59-92f5-67a261d23b44', '{"name": "GENERAL ASGG 12 CGTB   1 Tn 5*", "brand": "GENERAL", "model": "ASGG 12 CGTB   1 Tn 5*", "opening_stock_qty": 0}', NULL, '2026-10-08 17:16:00.841635+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('f1c3246d-a592-451a-bb50-f71c6105e6d9', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', 'f306cbd1-f4fb-45e2-b408-ab8cb46e536b', '{"name": "GENERAL ASGG12CGWA-B 1 T INV AC 4*", "brand": "GENERAL", "model": "ASGG12CGWA-B 1 T INV AC 4*", "opening_stock_qty": 0}', NULL, '2026-10-08 17:16:18.57077+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('6f894afd-5cd8-4f66-8bc5-46cc55a8d149', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '953f64bb-183a-4dcc-ad51-4a9b8d1ba754', '{"name": "GENERAL ASGG 12 CKWA-B 1.OT INV AC 3*", "brand": "GENERAL", "model": "ASGG 12 CKWA-B 1.OT INV AC 3*", "opening_stock_qty": 0}', NULL, '2026-10-08 17:16:40.348617+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('038de2cd-6737-4d4f-82b1-d540eb4674c3', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '06521486-9173-4469-a926-09fdde8f7fba', '{"name": "GENERAL ASGG 12 CPWA-B 1T INV AC3*", "brand": "GENERAL", "model": "ASGG 12 CPWA-B 1T INV AC3*", "opening_stock_qty": 0}', NULL, '2026-10-08 17:17:23.484745+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('b75a63db-df8d-47df-a2f8-1dbd1fb46183', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '03316b63-3179-42e1-9210-df9a792649a9', '{"name": "GENERAL ASGG 18 CEAC-B 1.5T INC AC 5*", "brand": "GENERAL", "model": "ASGG 18 CEAC-B 1.5T INC AC 5*", "opening_stock_qty": 0}', NULL, '2026-10-08 17:17:40.86429+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('9d72dc8e-2eba-442a-8fdb-3b3dc77dc796', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', 'a644739a-efcc-47fb-8117-bcfc36c4b41e', '{"name": "GENERAL ASGG 18 CETB-B 1.5T INV AC 5*", "brand": "GENERAL", "model": "ASGG 18 CETB-B 1.5T INV AC 5*", "opening_stock_qty": 0}', NULL, '2026-10-08 17:18:02.716345+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('dc2e6d02-a0cd-4d9b-9c57-01ed3fc2fb32', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '0dd497cc-caf0-4134-9437-535b16365a0b', '{"name": "FORMENTY FM 32 HDRPT1", "brand": "FORMENTY", "model": "FM 32 HDRPT1", "opening_stock_qty": 0}', NULL, '2026-10-09 11:29:46.017984+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('043c1939-7f27-4dd1-bcac-53e695a9dd7b', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '75b4ac90-2d54-4c52-aaae-1c86b6554ae8', '{"name": "FORMENTY FM32HDSPB2YU LED- LUMINOR SERIES", "brand": "FORMENTY", "model": "FM32HDSPB2YU LED- LUMINOR SERIES", "opening_stock_qty": 0}', NULL, '2026-10-09 11:30:01.806721+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('33840c27-25ee-481e-b5c0-67d6f43d5135', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', 'f1405e84-41dc-4b22-bd87-bd9006a17c81', '{"name": "FORMENTY FM 32 HDSPT2 SMART", "brand": "FORMENTY", "model": "FM 32 HDSPT2 SMART", "opening_stock_qty": 0}', NULL, '2026-10-09 11:30:14.054387+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('64aa9f28-e08a-4653-a4ae-9281c5a96b42', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '8590701f-97f0-486e-9b47-ced013bd4c1d', '{"name": "FORMENTY FM32HDSQSPR1DX Q LED-SPECTRA SERIES", "brand": "FORMENTY", "model": "FM32HDSQSPR1DX Q LED-SPECTRA SERIES", "opening_stock_qty": 0}', NULL, '2026-10-09 11:30:41.699172+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('8d59d932-9aa8-48c2-a8b1-d4b005467205', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '7999322a-f1bb-4a0f-a72e-475b819b6a3f', '{"name": "FORMENTY FM43UHDQSPR4DX QLED-SPECTRA SERIES", "brand": "FORMENTY", "model": "FM43UHDQSPR4DX QLED-SPECTRA SERIES", "opening_stock_qty": 0}', NULL, '2026-10-09 11:30:57.553489+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('d4cfbe51-1a72-4c7a-8b21-2cd4d10c8bee', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '8531cbb7-5457-49c3-9e0d-4529700e42bf', '{"name": "FORMENTY FM55UHDQSPR5DX Q LED- SPECTRA SERIES", "brand": "FORMENTY", "model": "FM55UHDQSPR5DX Q LED- SPECTRA SERIES", "opening_stock_qty": 0}', NULL, '2026-10-09 11:31:11.920615+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('7293ad19-9f8a-4fe4-adc6-9c67a7dab70a', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '4958f751-6916-45fc-8725-d0bf223ac9c9', '{"name": "FORMENTY LED FMTY FM32HDSQTVDXB1 Google Q Led VELORA", "brand": "FORMENTY", "model": "LED FMTY FM32HDSQTVDXB1 Google Q Led VELORA", "opening_stock_qty": 0}', NULL, '2026-10-09 11:32:19.460036+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('00449b8a-2b77-4e17-ae6c-df3b1a041191', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '730cc975-b1e6-48b6-94dc-8f5686b98c7a', '{"name": "FORMENTY LED FMTY -FM32HDSQTVWWCR GOOGLE Q LED TV -Cinara", "brand": "FORMENTY", "model": "LED FMTY -FM32HDSQTVWWCR GOOGLE Q LED TV -Cinara", "opening_stock_qty": 0}', NULL, '2026-10-09 11:32:31.151671+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('291fa597-b9e4-401d-bde2-6e98ea010a85', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '00d31b1c-02fe-454f-ad9c-3bd47c74f7d0', '{"name": "FORMENTY LED FMTY FM32HDTVDXB1 GOOGLE  QLED TV VELORA", "brand": "FORMENTY", "model": "LED FMTY FM32HDTVDXB1 GOOGLE  QLED TV VELORA", "opening_stock_qty": 0}', NULL, '2026-10-09 11:32:54.063222+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('40dbd592-446a-407a-bb14-c8159ead3695', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '9ab2a8e4-e693-47f2-9024-c1a791556c8f', '{"name": "FORMENTY LED FMTY FM40FDSQTVDXB2 Google Q Led VELORA", "brand": "FORMENTY", "model": "LED FMTY FM40FDSQTVDXB2 Google Q Led VELORA", "opening_stock_qty": 0}', NULL, '2026-10-09 11:33:14.210849+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('c130b88f-46ed-4d07-9089-4ec0112132f8', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '73cfffaa-0a4c-4841-8df0-9a5a9393b343', '{"name": "FORMENTY LED FMTY FM43UHDQTVDXB4 4K UHD Q LED VELORA", "brand": "FORMENTY", "model": "LED FMTY FM43UHDQTVDXB4 4K UHD Q LED VELORA", "opening_stock_qty": 0}', NULL, '2026-10-09 11:33:47.619372+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('f8e318bf-f0ea-465d-a7db-6a0966432b30', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '4c32c360-3147-44e1-b8f6-4ade7ab898b1', '{"name": "FORMENTY LED FMTY -FM55UHDQTVDXB5 GOOGLE Q LED TV VELORA", "brand": "FORMENTY", "model": "LED FMTY -FM55UHDQTVDXB5 GOOGLE Q LED TV VELORA", "opening_stock_qty": 0}', NULL, '2026-10-09 11:34:05.174657+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('4c41691d-8e40-487a-aa95-a2da511fbd78', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '7100a1c9-9c26-447b-b802-c50f699ef157', '{"name": "GENERAL ASGG 24CEAC-B 2T INV AC 5*", "brand": "GENERAL", "model": "ASGG 24CEAC-B 2T INV AC 5*", "opening_stock_qty": 0}', NULL, '2026-10-09 17:54:22.402935+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('bc8290ec-09eb-4806-83ed-56eacb2efe45', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '94a0f4bd-acc7-40bc-832b-b4e1b4afae85', '{"name": "GENERAL ASGG 22CNWA-B 1.8T INV AC 3*", "brand": "GENERAL", "model": "ASGG 22CNWA-B 1.8T INV AC 3*", "opening_stock_qty": 0}', NULL, '2026-10-09 17:55:29.869288+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('08e9899a-b5ae-411a-83c6-e133bb71f4d8', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '15b44915-d3de-434f-b570-e4e605161410', '{"name": "GENERAL ASGG 18 CNWA-B 1.5T INV AC 3*", "brand": "GENERAL", "model": "ASGG 18 CNWA-B 1.5T INV AC 3*", "opening_stock_qty": 0}', NULL, '2026-10-09 17:56:02.364721+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('9ca3c427-ea8b-4d06-9168-664324f16b25', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '2f6867f2-d0a6-4f11-91cc-06d9eda1e250', '{"name": "GENERAL ASGG 18 CKWA-B 1.5T INV AC 3*", "brand": "GENERAL", "model": "ASGG 18 CKWA-B 1.5T INV AC 3*", "opening_stock_qty": 0}', NULL, '2026-10-09 17:56:28.124602+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('e98c7abf-503c-4a63-9844-efff320fdc91', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'SHOP_PERMANENTLY_DELETED', 'shop', '7fd63368-cfd3-408d-840a-ccc20942bba8', '{"city": null, "name": "KMK ELECTRONICS&HOME APPLIANCES"}', NULL, '2026-10-09 17:40:26.197631+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('c6a427db-cd39-4ab9-828a-cb64a0b0237f', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '48f9f792-e076-4970-9506-fd1c589a344c', '{"name": "FORMENTY AC FMTY Split Inverter FRIO 1.0T3*-Fm12ininv3froed", "brand": "FORMENTY", "model": "AC FMTY Split Inverter FRIO 1.0T3*-Fm12ininv3froed", "opening_stock_qty": 0}', NULL, '2026-10-09 17:46:02.662567+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('6ff2b2da-4949-4939-9008-9c292272e9f7', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '67303761-7b54-48c5-8f2a-3898a2a33a48', '{"name": "CARRIER AC CARRIER 18K INDUS GXI ALPHA HYBRIDJET 1.5 TON 3*", "brand": "CARRIER", "model": "AC CARRIER 18K INDUS GXI ALPHA HYBRIDJET 1.5 TON 3*", "opening_stock_qty": 0}', NULL, '2026-10-09 17:48:06.262595+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('5bbb1deb-a632-4c1c-9e16-c4c9937147b0', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', 'b837c539-50a3-4150-9fe9-919c841edc00', '{"name": "CARRIER AC CARRIER 19K EXCEED LUMO GXI 1.5 T 5*", "brand": "CARRIER", "model": "AC CARRIER 19K EXCEED LUMO GXI 1.5 T 5*", "opening_stock_qty": 0}', NULL, '2026-10-09 17:48:32.256582+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('93ab6756-ecf9-4f26-9d5c-3b92ff31f8b1', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', 'c470be68-a897-4619-a664-8de8de92bf20', '{"name": "CARRIER AC MIDEA 12K SANTIS NXG (V-PRO) DLX INV 1 TON 3*", "brand": "CARRIER", "model": "AC MIDEA 12K SANTIS NXG (V-PRO) DLX INV 1 TON 3*", "opening_stock_qty": 0}', NULL, '2026-10-09 17:48:52.548906+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('e334981a-c6fd-4c8c-b96e-7359d50d8b89', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', 'a2943f0e-4eac-4199-bec0-b45cdb2e2a96', '{"name": "CARRIER CARRIER 24K XCEED EDGE GXIINV AC 5*", "brand": "CARRIER", "model": "CARRIER 24K XCEED EDGE GXIINV AC 5*", "opening_stock_qty": 0}', NULL, '2026-10-09 17:49:21.769679+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('ccd98d22-debb-49a6-b543-04227609d852', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '944814a5-6009-4f50-b13e-131dad62243e', '{"name": "CARRIER CARRIER AC 12K XCEL EDGE GXI INV AC 5*", "brand": "CARRIER", "model": "CARRIER AC 12K XCEL EDGE GXI INV AC 5*", "opening_stock_qty": 0}', NULL, '2026-10-09 17:49:38.784396+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('6f26f59c-62cd-4ebd-98eb-9106d56b9aad', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '90492d3d-ac36-4a1f-bc8f-b9005c976939', '{"name": "CARRIER CARRIER AC 24K XCEED EDGE GXI ALPHA HYBRIDJET 3*", "brand": "CARRIER", "model": "CARRIER AC 24K XCEED EDGE GXI ALPHA HYBRIDJET 3*", "opening_stock_qty": 0}', NULL, '2026-10-09 17:49:52.37412+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('d797968b-57b1-47e0-a959-d05861a3cb72', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', 'fa8b239a-c9e1-43d7-bf5d-37c9e0a3d0dc', '{"name": "GENERAL ECCGA4 EXTENDED COMPREHNSIVE COVER(F/I/C)4YR", "brand": "GENERAL", "model": "ECCGA4 EXTENDED COMPREHNSIVE COVER(F/I/C)4YR", "opening_stock_qty": 0}', NULL, '2026-10-09 17:52:48.561338+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('2d4d97a3-2499-45d4-b195-70a5c05fb583', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '26d7311e-4fe3-49bf-bd63-037cf843adbf', '{"name": "GENERAL ASSGG24CGWA-B 2T INV AC 4*", "brand": "GENERAL", "model": "ASSGG24CGWA-B 2T INV AC 4*", "opening_stock_qty": 0}', NULL, '2026-10-09 17:53:04.802408+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('931fe014-2526-41eb-9261-35c8ea9bbc28', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', 'ea453d9a-85fb-4293-b1cc-2cabf84cd453', '{"name": "GENERAL ASGG30CEAC.B 2.5 T INV AC 5*", "brand": "GENERAL", "model": "ASGG30CEAC.B 2.5 T INV AC 5*", "opening_stock_qty": 0}', NULL, '2026-10-09 17:53:30.112812+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('e8ce2daa-7ab7-4113-995d-f3bb4b0438f9', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '5afc04e5-5ae4-4f5e-8757-24c9942f0e96', '{"name": "GENERAL ASGG 24 CPAB-B 3*", "brand": "GENERAL", "model": "ASGG 24 CPAB-B 3*", "opening_stock_qty": 0}', NULL, '2026-10-09 17:53:47.19933+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('3c87c86e-88fa-4fcc-9278-a7e2fda00f59', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_CREATED', 'product', '63bea063-3723-4969-9d54-24bf1ddb5917', '{"name": "GENERAL ASGG 24 CGAA-B 2.0T INV AC 5*", "brand": "GENERAL", "model": "ASGG 24 CGAA-B 2.0T INV AC 5*", "opening_stock_qty": 0}', NULL, '2026-10-09 17:54:09.133437+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('0ea8d562-0c95-46d6-8b90-890e99931046', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'CATEGORY_CREATED', 'category', '1fc15e19-a356-47e2-b5ff-57183448f844', '{"name": "VC COOLER", "has_dual_serial": false}', NULL, '2026-10-09 18:53:23.624647+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('0fa440cb-3e82-48be-a4b8-03318f56a293', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'BULK_PRODUCTS_CREATED', 'product', 'd02f27ce-8ced-49a0-bc56-cc019d184640', '{"brand": "HAIER", "models": ["HVC-1050GHC:HIL/DF", "HVC-305GT5:VISI COOLER/GLASS DOOR", "HVC-405GT5:VISI COOLER/GLASS DOOR", "HVC-505GT5:VISI COOLER/GLASS DOOR"], "category_id": "1fc15e19-a356-47e2-b5ff-57183448f844", "category_name": "VC COOLER", "created_count": 4, "skipped_count": 0}', NULL, '2026-10-09 18:53:48.510399+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('dec31200-ecef-44a5-9886-db402d72085b', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'CATEGORY_CREATED', 'category', '7b507da6-509e-4af1-91a9-c9a827c4f2b3', '{"name": "WATER HEATER", "has_dual_serial": false}', NULL, '2026-10-09 18:54:02.45608+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('8f4d5556-7016-4e05-8f52-d823cb221b8b', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'BULK_PRODUCTS_CREATED', 'product', '94784edd-0fd3-4cc8-b9ba-d561d2e318e9', '{"brand": "HAIER", "models": ["EI3V-ZYON 3kw(I):W/H", "ES10V-PRECIS:ES10V-PRECIS", "ES10V-VL:ES10V-VL", "WH HAIER ES 6V-Q1(H)"], "category_id": "7b507da6-509e-4af1-91a9-c9a827c4f2b3", "category_name": "WATER HEATER", "created_count": 4, "skipped_count": 0}', NULL, '2026-10-09 18:54:27.356299+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('1b6d56fc-93ad-428a-8ce7-50f2fb78754d', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'CATEGORY_CREATED', 'category', '29b08f28-6149-437c-8a16-80fb4186bb28', '{"name": "W Dispencer", "has_dual_serial": false}', NULL, '2026-10-09 18:54:38.259866+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('798e3a36-34ca-47f8-8d4d-6715eda506f8', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'BULK_PRODUCTS_CREATED', 'product', '4bee8f4a-f9e8-4134-ac2b-b0409ec3ac6f', '{"brand": "HAIER", "models": ["HWD-3WTT:HIL/WD"], "category_id": "29b08f28-6149-437c-8a16-80fb4186bb28", "category_name": "W Dispencer", "created_count": 1, "skipped_count": 0}', NULL, '2026-10-09 18:54:59.87+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('c67d0789-7fa4-45e2-b426-2437ff3d747b', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'BULK_PRODUCTS_CREATED', 'product', 'ebcb61f5-5f10-4df6-809a-a5d81b383fbe', '{"brand": "TEST_BRAND", "models": ["MOD_001", "MOD_002"], "category_id": "a61627a9-d0a7-49b8-af5f-56c872026561", "category_name": "AC", "created_count": 2, "skipped_count": 0}', NULL, '2026-10-09 18:18:13.847905+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('fc69277d-b517-48f3-962a-187b1dad9e41', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'BULK_PRODUCTS_CREATED', 'product', '044e780d-37ab-4bfb-a93f-28d135453547', '{"brand": "HAIER", "models": ["AC HAIER HS12C-TCS3B 1T 3* (INV)", "HS12V-AOW3BN-INV:AC", "HS 12V PNW3BN-INV AC", "HS 13C POW3BN-INV:AC", "HS13E-TXG5B(INV):AC", "HS13K-PYG5BE-INV:AC", "HS13K-PZB3BN-INV:AC", "HS 18EP-TXS5BN-INV:AC", "HS19E-TXW5BN-INV:AC", "HSI 12VP-S3NB-I:AC", "HSI 13VP-G3NB-I:AC", "HSI 14EHD-GAI5NB-I:AC", "HSI 14KU-CAI4NB-I:AC", "HSI 19EHD-GAI5NB-I:AC", "HSI 48N-G3NB-I:AC", "HSI 48VP-S3NB-I:AC", "HSI 50CP-S3NB-I:AC"], "category_id": "a61627a9-d0a7-49b8-af5f-56c872026561", "category_name": "AC", "created_count": 17, "skipped_count": 0}', NULL, '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('cb3971a1-6654-4c08-948d-75bbe4b3117e', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'CATEGORY_CREATED', 'category', '360e12f4-e4b9-4a67-9169-290f2ac8dc67', '{"name": "AIR FRYER", "has_dual_serial": false}', NULL, '2026-10-09 18:35:58.260405+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('c973950e-aca7-42ce-89fd-24273c9d6af4', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'BULK_PRODUCTS_CREATED', 'product', 'c27f679f-759c-4bd6-b0b1-038cd6d5aec2', '{"brand": "HAIER", "models": ["HAF-D503B:PIP", "HAF-M403I:PIP"], "category_id": "a61627a9-d0a7-49b8-af5f-56c872026561", "category_name": "AC", "created_count": 2, "skipped_count": 0}', NULL, '2026-10-09 18:36:29.813714+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('a634b98c-ff41-4a41-b540-3020afaea8ef', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_UPDATED', 'product', 'd3dc8b67-a0ed-436f-965f-013c4f1e9efc', '{"name": "HAIER HAF-M403I:PIP", "is_active": true}', NULL, '2026-10-09 18:37:10.85252+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('4db0317b-c5e6-40e3-aa7d-5412765d8330', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_UPDATED', 'product', 'c27f679f-759c-4bd6-b0b1-038cd6d5aec2', '{"name": "HAIER HAF-D503B:PIP", "is_active": true}', NULL, '2026-10-09 18:37:29.504476+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('3c691434-1349-4cd0-8e24-f0e4287fee2b', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'CATEGORY_CREATED', 'category', 'd690ccfe-6e58-4055-a200-3ea07d4134b3', '{"name": "AUTOMATIC WM", "has_dual_serial": false}', NULL, '2026-10-09 18:41:56.52544+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('35ed3290-6575-42b7-a90c-8117b4f5135a', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'BULK_PRODUCTS_CREATED', 'product', '455c98c4-084e-496c-bba5-de96ce483ba6', '{"brand": "HAIER", "models": ["HW70-IM12929:PUNE", "HW70-IM12929BK:PUNE", "HW90-DM14F9BKU1: PUNE", "HWD120-DM14F11BKU1:PUNE", "HWM60-1269DB:PUNE", "HWM70-306ES5N1:PUNE", "HWM70-306S8:PUNE", "HWM 75-678EBK:PUNE", "HWM75-H678ES5:NOIDA", "HWM75-H826S6:NOIDA", "HWM80-310BK:PUNE", "HWM 80-678BK:PUNE", "HWM 80-688 S8:NOIDA", "HWM 80-H320BK:NOIDA", "HWM85-316BK:NOIDA", "HWM90-H688BK:NOIDA"], "category_id": "d690ccfe-6e58-4055-a200-3ea07d4134b3", "category_name": "AUTOMATIC WM", "created_count": 16, "skipped_count": 0}', NULL, '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('6b8837a6-4e16-4319-86b0-327aafd74b42', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'BULK_PRODUCTS_CREATED', 'product', '00e9b551-e68a-4da7-aa0f-cdd60e73332a', '{"brand": "HAIER", "models": ["HFC-230SPW4:HTDF/HAIER", "HFC-300GM5:GT DF/HAIER", "HFC-400GM5:GT DF/HAIER"], "category_id": "5d3395d9-808e-4fff-815c-a0facdf8bbdb", "category_name": "FREEZER", "created_count": 3, "skipped_count": 0}', NULL, '2026-10-09 18:46:41.488497+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('45e340f1-124a-4dd1-a84c-f9f5f7769231', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'CATEGORY_CREATED', 'category', '414278e1-8d2a-4824-859e-87b8aaffb4a0', '{"name": "KITCHEN APPLIANCES", "has_dual_serial": false}', NULL, '2026-10-09 18:48:19.006625+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('b52e2896-5408-4f68-ba3d-25b1aabb1178', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'BULK_PRODUCTS_CREATED', 'product', 'dd75fa8a-769f-4088-a01a-8557868b6bcd', '{"brand": "HAIER", "models": ["HIC-653FCF-O:FFD/", "HIC-654FCF-O:FFD/", "HIC-Q27326-IN:ODM", "HIH-G60HM-G:Touch&LED Display"], "category_id": "5d3395d9-808e-4fff-815c-a0facdf8bbdb", "category_name": "FREEZER", "created_count": 4, "skipped_count": 0}', NULL, '2026-10-09 18:48:44.148858+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('778e6add-3bd9-48d2-a9b1-d9a7f437180a', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'BULK_PRODUCTS_CREATED', 'product', '7c3730ec-90c4-460b-8dff-82b9dc8a33eb', '{"brand": "HAIER", "models": ["43 A9UG:HIL/LED", "43P7 Pro : PUNE", "50P7 Pro : PUNE", "55P7 Pro : PUNE", "H 32S80 FFX:PUNE", "H32S80GFX: PUNE", "H55M80FUX:PUNE", "H55 S80 FUX:PUNE", "H65M80FUX:PUNE", "H 65 S80 FUX:PUNE", "H75K 85 FUX:PUNE", "LE32K6600GA:PUNE", "LE32K8200GT:PUNE", "LE55K800UGT:PUNE", "LE65B8500U:PAL/BG/BLACK/HIL", "LE H32K 82GX:PUNE", "LE H43K85FFX:PUNE", "LE H50K85FUX:PUNE", "LE H55K85 FUX:PUNE", "LE H65K 85 FUX:PUNE"], "category_id": "043d664f-f89e-4187-99f0-ff9bceb2575c", "category_name": "TV", "created_count": 20, "skipped_count": 0}', NULL, '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('f054b81b-d802-448f-b045-7b2e89b5d1a8', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'CATEGORY_CREATED', 'category', 'e8df29cf-abd3-4e8d-9718-cb2d3365e860', '{"name": "MICRO WAVE OVEN", "has_dual_serial": false}', NULL, '2026-10-09 18:50:08.73165+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('472449d2-bcd4-4737-a846-0f740d1d24e6', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'BULK_PRODUCTS_CREATED', 'product', '2a210e8b-c6ab-4483-83f7-03bf501aac42', '{"brand": "HAIER", "models": ["HIL2001CSSH:20L/convenction/haier", "HIL2002CSSH:20 LTR CONVECTION", "HIL2002GBPH:INDIA/HAIER", "HIL2002MFPH:20L SOLO", "HIL 20V1 MBPD:MWO", "HIL2301MBEJ:23L/Haier/Solo", "MWO HIL3001CBSH:IN/HAIER  30 L  CON"], "category_id": "e8df29cf-abd3-4e8d-9718-cb2d3365e860", "category_name": "MICRO WAVE OVEN", "created_count": 7, "skipped_count": 0}', NULL, '2026-10-09 18:50:24.811284+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('43f5f1eb-75d0-4268-af0c-f3a4b08ac343', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'BULK_PRODUCTS_CREATED', 'product', '1ccb8e45-c1d5-44d1-b13a-005a31e720b2', '{"brand": "HAIER", "models": ["HEB-452TS-P:REF/HAIER/445L", "HEF-253GS-P:REF/HAIER/240L", "HES-690GK:REF/Haier/596L", "HRB-2871EMSA-P:REF/HAIER/237L", "HRB-2872EKGA-P:REF/HAIER/237L", "HRB-2872EMGA-P REF/Haier/237L", "HRB-3152 PKGA-P:REF/HAIER/265L", "HRB-3152PKG-P", "HRB-3501BS-P:REF/Haier/300L", "HRB-3752BGKA-P:REF/Haier/325L", "HRB-3752PKGA-P:REF/HAIER/325L", "HRB-3752PMGA-P:REF/Haier/325L", "HRB-4052PKGA-P:REF/HAIER/355L", "HRB-4052PMGA-P:REF/HAIER/355L", "HRB-4053PKG-P:REF/HAIER/355L", "HRB-4952BIS-P:REF/HAIER/445L", "HRB-4952CKGA-P:REF/HAIER/445L", "HRB-600IS:REF/Haier/520L", "HRB-700KGU1:REF/Haier/630L", "HRF-2901EMSA-P:REF/Haier/240L", "HRF-2901 IERBA-P:REF/HAIER/240L", "HRF-2902EKGA-P:REF/Haier/240L", "HRF-2902 EWGA-P:REF/HAIER/240L", "HRF-2902 IEMSA-P:REF/Haier/240L", "HRF-2902IERBA-P:REF/Haier/240L", "HRF-3182EIS-P:REF/Haier/268L", "HRF-3182PKGA-P:REF/HAIER/268L", "HRF-3782PLKGA-P:REF/HAIER/328L", "HRF-4083BIS-P:REF/HAIER/358L", "HRF-4083PLKG-P:REF/Haier/358L", "HRF-5252BGK-N:REF/HAIER/475L", "HRS-615FS:REF/HAIER/540L", "HRS-682SS:REF/Haier/602 L", "HRT-683GOG-P:REF/Haier/598L", "HRD-1861BBR-N:REF/Haier/165L", "HRD-1953CRC:REF/Haier/195L", "HRD-2052BBR-P:REF/HAIER/185L", "HRD-2101 BBRA-P:REF/HAIER/190L", "HRD-2101BBR-P:REF/Haier/190L", "HRD-2103CBS-P:REF/HAIER/190L", "HRD-2105BNS-P:REF/Haier/190L", "HRD-2105CBSA-P:REF/Haier/190L", "HRD-2261SMMA-N:REF/HAIER/205L", "HRD-2261SPMA-N:REF/HAIER/205L", "HRD-2261SRMA-N:REF/HAIER/205L", "HRD-2561SGSA-N:REF/HAIER/235L", "HRD-752KSA-MINIBAR/HAIER/50L", "REF HAIER HRD 2115PMGA-N:REF/HAIER/190L"], "category_id": "3866bb27-b9b4-40c1-99b8-2aed06198a18", "category_name": "REFERIGERATOR", "created_count": 48, "skipped_count": 0}', NULL, '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('4c90596f-3063-4006-9a3c-add0c28ba1a8', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'CATEGORY_CREATED', 'category', '3e8eaf81-f945-4859-aceb-b65565116494', '{"name": "VACCUM CLEANER", "has_dual_serial": false}', NULL, '2026-10-09 18:52:55.416969+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('377e015b-2bb0-49f4-a5fb-a2eafcd5313e', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'BULK_PRODUCTS_CREATED', 'product', 'af4b107b-a497-41a9-b712-cabe548a3efa', '{"brand": "HAIER", "models": ["Civic X11 :Robot Vacum Cleaner", "Civic X11 Pro:Robot Vacum Cleaner", "PRObotDTX/ROBVAC/LDS Vaccum Cleaner", "TH27U1:HR/T/WHITE Vaccum Cleaner"], "category_id": "3e8eaf81-f945-4859-aceb-b65565116494", "category_name": "VACCUM CLEANER", "created_count": 4, "skipped_count": 0}', NULL, '2026-10-09 18:53:12.46363+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('ae7b0cd4-c478-4b9b-bccb-482fae2f9996', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'BULK_PRODUCTS_CREATED', 'product', '0c2c6f8e-0df2-4c22-9cfd-07d96ebdb121', '{"brand": "HAIER", "models": ["HTW100-196BK", "HTW 120-178BK:NOIDA", "HTW 120-196BK:NOIDA", "HTW140-178BK:NOIDA", "HTW70-178BKN:NOIDA", "HTW70-178N:PUNE", "HTW75-178BBK", "HTW80-178:NOIDA", "HTW85-178BBKN:NOIDA", "HTW85-178BKN1", "HTW85-178FL:NOIDA", "HTW85-178 Noida", "HTW85-178PBK", "HTW90-196BBK:NOIDA"], "category_id": "c0f349e1-9209-422e-b304-a5f3d0bbf5b8", "category_name": "SEMI WM", "created_count": 14, "skipped_count": 0}', NULL, '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('24c97f90-1b26-4314-afdf-03212cb15f46', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_DEACTIVATED', 'product', 'dd75fa8a-769f-4088-a01a-8557868b6bcd', '{"name": "HAIER HIC-653FCF-O:FFD/"}', NULL, '2026-10-09 18:56:38.706392+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('4004c443-a4a4-4be7-a4d3-d1c33d3553d2', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_DEACTIVATED', 'product', '15ce6ecf-cf19-44c9-81da-717aa944fac0', '{"name": "HAIER HIC-654FCF-O:FFD/"}', NULL, '2026-10-09 18:56:53.606612+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('c51bde7f-5362-4247-a1a3-8e15c012ad07', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_DEACTIVATED', 'product', 'eeb482ba-1285-4e93-aea0-669996f9e157', '{"name": "HAIER HIC-Q27326-IN:ODM"}', NULL, '2026-10-09 18:57:04.450386+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('ea8bef43-7d88-4ec1-a81c-98a7179f4aa9', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_DEACTIVATED', 'product', '8ec9b0fb-4689-4b54-a9a6-7cd10884163a', '{"name": "HAIER HIH-G60HM-G:Touch&LED Display"}', NULL, '2026-10-09 18:57:25.96249+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('fcddc961-7177-4652-8497-12fd3b03ada7', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_UPDATED', 'product', 'dd75fa8a-769f-4088-a01a-8557868b6bcd', '{"name": "HAIER HIC-653FCF-O:FFD/", "is_active": false}', NULL, '2026-10-09 19:09:20.224212+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('dbca877a-de15-47a7-b25a-8c3c134f8f87', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_UPDATED', 'product', '15ce6ecf-cf19-44c9-81da-717aa944fac0', '{"name": "HAIER HIC-654FCF-O:FFD/", "is_active": false}', NULL, '2026-10-09 19:09:30.733889+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('186ed259-13e5-448e-bcfa-4b4b84ad174c', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_UPDATED', 'product', 'eeb482ba-1285-4e93-aea0-669996f9e157', '{"name": "HAIER HIC-Q27326-IN:ODM", "is_active": false}', NULL, '2026-10-09 19:09:40.37862+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('4827f1ca-e53a-4d91-944e-95c88d056aa4', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_UPDATED', 'product', '8ec9b0fb-4689-4b54-a9a6-7cd10884163a', '{"name": "HAIER HIH-G60HM-G:Touch&LED Display", "is_active": false}', NULL, '2026-10-09 19:09:51.267595+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('e86caf36-5740-453b-a2d8-7d209881870a', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_REACTIVATED', 'product', 'dd75fa8a-769f-4088-a01a-8557868b6bcd', '{"name": "HAIER HIC-653FCF-O:FFD/"}', NULL, '2026-10-09 19:10:06.309896+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('fdc53486-122d-4b6d-b90f-b96ff8fc0b16', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_REACTIVATED', 'product', '15ce6ecf-cf19-44c9-81da-717aa944fac0', '{"name": "HAIER HIC-654FCF-O:FFD/"}', NULL, '2026-10-09 19:10:09.297252+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('86ee341e-467f-4fa9-aea0-866189b362ab', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_REACTIVATED', 'product', 'eeb482ba-1285-4e93-aea0-669996f9e157', '{"name": "HAIER HIC-Q27326-IN:ODM"}', NULL, '2026-10-09 19:10:13.623054+05:30');
INSERT INTO public.audit_log (id, user_id, device_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES ('3c44e37a-7634-498f-8d35-d9222eaaeeed', '656f2005-9e50-4d61-9009-e9356e0a9c46', NULL, 'PRODUCT_REACTIVATED', 'product', '8ec9b0fb-4689-4b54-a9a6-7cd10884163a', '{"name": "HAIER HIH-G60HM-G:Touch&LED Display"}', NULL, '2026-10-09 19:10:17.422178+05:30');


--
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.categories (id, name, is_active, created_at, updated_at, has_dual_serial) VALUES ('a61627a9-d0a7-49b8-af5f-56c872026561', 'AC', true, '2026-10-08 16:00:02.724115+05:30', '2026-10-08 16:00:02.724115+05:30', true);
INSERT INTO public.categories (id, name, is_active, created_at, updated_at, has_dual_serial) VALUES ('3866bb27-b9b4-40c1-99b8-2aed06198a18', 'REFERIGERATOR', true, '2026-10-08 16:03:02.90933+05:30', '2026-10-08 16:03:02.90933+05:30', false);
INSERT INTO public.categories (id, name, is_active, created_at, updated_at, has_dual_serial) VALUES ('043d664f-f89e-4187-99f0-ff9bceb2575c', 'TV', true, '2026-10-08 16:03:49.907974+05:30', '2026-10-08 16:03:49.907974+05:30', false);
INSERT INTO public.categories (id, name, is_active, created_at, updated_at, has_dual_serial) VALUES ('5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'FREEZER', true, '2026-10-08 16:58:41.867432+05:30', '2026-10-08 16:58:41.867432+05:30', false);
INSERT INTO public.categories (id, name, is_active, created_at, updated_at, has_dual_serial) VALUES ('360e12f4-e4b9-4a67-9169-290f2ac8dc67', 'AIR FRYER', true, '2026-10-09 18:35:58.260405+05:30', '2026-10-09 18:35:58.260405+05:30', false);
INSERT INTO public.categories (id, name, is_active, created_at, updated_at, has_dual_serial) VALUES ('c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'SEMI WM', true, '2026-10-08 16:02:46.527857+05:30', '2026-10-08 16:02:46.527857+05:30', false);
INSERT INTO public.categories (id, name, is_active, created_at, updated_at, has_dual_serial) VALUES ('d690ccfe-6e58-4055-a200-3ea07d4134b3', 'AUTOMATIC WM', true, '2026-10-09 18:41:56.52544+05:30', '2026-10-09 18:41:56.52544+05:30', false);
INSERT INTO public.categories (id, name, is_active, created_at, updated_at, has_dual_serial) VALUES ('414278e1-8d2a-4824-859e-87b8aaffb4a0', 'KITCHEN APPLIANCES', true, '2026-10-09 18:48:19.006625+05:30', '2026-10-09 18:48:19.006625+05:30', false);
INSERT INTO public.categories (id, name, is_active, created_at, updated_at, has_dual_serial) VALUES ('e8df29cf-abd3-4e8d-9718-cb2d3365e860', 'MICRO WAVE OVEN', true, '2026-10-09 18:50:08.73165+05:30', '2026-10-09 18:50:08.73165+05:30', false);
INSERT INTO public.categories (id, name, is_active, created_at, updated_at, has_dual_serial) VALUES ('3e8eaf81-f945-4859-aceb-b65565116494', 'VACCUM CLEANER', true, '2026-10-09 18:52:55.416969+05:30', '2026-10-09 18:52:55.416969+05:30', false);
INSERT INTO public.categories (id, name, is_active, created_at, updated_at, has_dual_serial) VALUES ('1fc15e19-a356-47e2-b5ff-57183448f844', 'VC COOLER', true, '2026-10-09 18:53:23.624647+05:30', '2026-10-09 18:53:23.624647+05:30', false);
INSERT INTO public.categories (id, name, is_active, created_at, updated_at, has_dual_serial) VALUES ('7b507da6-509e-4af1-91a9-c9a827c4f2b3', 'WATER HEATER', true, '2026-10-09 18:54:02.45608+05:30', '2026-10-09 18:54:02.45608+05:30', false);
INSERT INTO public.categories (id, name, is_active, created_at, updated_at, has_dual_serial) VALUES ('29b08f28-6149-437c-8a16-80fb4186bb28', 'W Dispencer', true, '2026-10-09 18:54:38.259866+05:30', '2026-10-09 18:54:38.259866+05:30', false);


--
-- Data for Name: devices; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.devices (id, device_uid, label, approved_by_id, approved_at, is_active, created_at) VALUES ('14a77e6e-6251-4bf8-b839-519260e205ae', '0300630b-cb12-4010-af1e-1c414df029f1', 'Android Godown Scanner', '656f2005-9e50-4d61-9009-e9356e0a9c46', '2026-10-08 13:14:39.15632+05:30', true, '2026-10-08 13:14:14.039885+05:30');
INSERT INTO public.devices (id, device_uid, label, approved_by_id, approved_at, is_active, created_at) VALUES ('e5621cd5-aaa0-40f3-9e5f-6c02b89d0d0a', '16b82feb-9760-4ded-a520-6d92be809377', 'Android Godown Scanner', '656f2005-9e50-4d61-9009-e9356e0a9c46', '2026-10-08 16:39:58.398456+05:30', true, '2026-10-08 16:38:56.960664+05:30');


--
-- Data for Name: inward_batches; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: inward_lines; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: outward_batches; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: outward_lines; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('4c32c360-3147-44e1-b8f6-4ade7ab898b1', 'FORMENTY LED FMTY -FM55UHDQTVDXB5 GOOGLE Q LED TV VELORA', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'FORMENTY', 'LED FMTY -FM55UHDQTVDXB5 GOOGLE Q LED TV VELORA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 11:34:05.174657+05:30', '2026-10-09 11:34:05.174657+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('48f9f792-e076-4970-9506-fd1c589a344c', 'FORMENTY AC FMTY Split Inverter FRIO 1.0T3*-Fm12ininv3froed', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'FORMENTY', 'AC FMTY Split Inverter FRIO 1.0T3*-Fm12ininv3froed', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:46:02.662567+05:30', '2026-10-09 17:46:02.662567+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('c470be68-a897-4619-a664-8de8de92bf20', 'CARRIER AC MIDEA 12K SANTIS NXG (V-PRO) DLX INV 1 TON 3*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'CARRIER', 'AC MIDEA 12K SANTIS NXG (V-PRO) DLX INV 1 TON 3*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:48:52.548906+05:30', '2026-10-09 17:48:52.548906+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('944814a5-6009-4f50-b13e-131dad62243e', 'CARRIER CARRIER AC 12K XCEL EDGE GXI INV AC 5*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'CARRIER', 'CARRIER AC 12K XCEL EDGE GXI INV AC 5*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:49:38.784396+05:30', '2026-10-09 17:49:38.784396+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('26d7311e-4fe3-49bf-bd63-037cf843adbf', 'GENERAL ASSGG24CGWA-B 2T INV AC 4*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASSGG24CGWA-B 2T INV AC 4*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:53:04.802408+05:30', '2026-10-09 17:53:04.802408+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('5afc04e5-5ae4-4f5e-8757-24c9942f0e96', 'GENERAL ASGG 24 CPAB-B 3*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGG 24 CPAB-B 3*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:53:47.19933+05:30', '2026-10-09 17:53:47.19933+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('94a0f4bd-acc7-40bc-832b-b4e1b4afae85', 'GENERAL ASGG 22CNWA-B 1.8T INV AC 3*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGG 22CNWA-B 1.8T INV AC 3*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:55:29.869288+05:30', '2026-10-09 17:55:29.869288+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('2f6867f2-d0a6-4f11-91cc-06d9eda1e250', 'GENERAL ASGG 18 CKWA-B 1.5T INV AC 3*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGG 18 CKWA-B 1.5T INV AC 3*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:56:28.124602+05:30', '2026-10-09 17:56:28.124602+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('7f4ac78e-a27b-428d-8d41-09e90e30beb2', 'ROCKWELL GFR1210F', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'GFR1210F', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 16:59:02.587912+05:30', '2026-10-08 16:59:17.376888+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('7c3730ec-90c4-460b-8dff-82b9dc8a33eb', 'HAIER 43 A9UG:HIL/LED', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', '43 A9UG:HIL/LED', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('382a659e-534c-42d4-8a46-c6932aedfedc', 'HAIER 43P7 Pro : PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', '43P7 Pro : PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('9e88be69-05e7-4434-867b-9fa7304608b4', 'HAIER 50P7 Pro : PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', '50P7 Pro : PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('6b8c9462-13fa-441f-9a2e-5a5243f0fff0', 'HAIER 55P7 Pro : PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', '55P7 Pro : PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('b3c1b461-b0f1-4c8e-9dbe-8dd56d2e6a95', 'ROCKWELL GFR 450 DDUC-5S', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'GFR 450 DDUC-5S', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 16:59:51.604125+05:30', '2026-10-08 16:59:51.604125+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('6df70d62-9f9e-4999-ae85-cbe9d6505fb6', 'HAIER H 32S80 FFX:PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'H 32S80 FFX:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('f93da442-7084-4860-b901-8d2d8f363825', 'HAIER H32S80GFX: PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'H32S80GFX: PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('a38e43de-aa99-449f-ae9c-574388066b6a', 'HAIER H55M80FUX:PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'H55M80FUX:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('e923b6ff-a3e6-45b6-8c42-6bf2dfcdde23', 'HAIER H55 S80 FUX:PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'H55 S80 FUX:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('7a0cf442-58b1-4030-93ae-8469a908f3da', 'HAIER H65M80FUX:PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'H65M80FUX:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('67e2cf26-196a-4f79-9fb9-e85f1459af11', 'HAIER H 65 S80 FUX:PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'H 65 S80 FUX:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('f6475590-c98d-476a-a905-8a52f6d15be1', 'HAIER H75K 85 FUX:PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'H75K 85 FUX:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('dd258f14-03be-4030-a437-6122a074763a', 'HAIER LE32K6600GA:PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'LE32K6600GA:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('4b971f0b-d85a-4338-a2cd-df38587b2f47', 'HAIER LE32K8200GT:PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'LE32K8200GT:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('8ea816ba-46a1-4e31-a633-7181699ef559', 'HAIER LE55K800UGT:PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'LE55K800UGT:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('578b5e52-fd20-4d85-9830-ab82fc2c0cc8', 'HAIER LE65B8500U:PAL/BG/BLACK/HIL', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'LE65B8500U:PAL/BG/BLACK/HIL', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('9689b60c-6d20-427c-9e5b-4ff6b5a94ebe', 'HAIER LE H32K 82GX:PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'LE H32K 82GX:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('ee653430-5eb0-46f2-9e4f-b38cc7c4550b', 'HAIER LE H43K85FFX:PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'LE H43K85FFX:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('2115f4c2-79bc-4b41-883b-e44c3d84f761', 'HAIER LE H50K85FUX:PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'LE H50K85FUX:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('1125b7e1-3d78-49d5-ae95-2c60bd89292c', 'HAIER LE H55K85 FUX:PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'LE H55K85 FUX:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('c6371687-6215-43a6-a8cc-7c9735f7c845', 'HAIER LE H65K 85 FUX:PUNE', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'HAIER', 'LE H65K 85 FUX:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:49:35.985667+05:30', '2026-10-09 18:49:35.985667+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('2a210e8b-c6ab-4483-83f7-03bf501aac42', 'HAIER HIL2001CSSH:20L/convenction/haier', NULL, 'e8df29cf-abd3-4e8d-9718-cb2d3365e860', 'HAIER', 'HIL2001CSSH:20L/convenction/haier', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:50:24.811284+05:30', '2026-10-09 18:50:24.811284+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('1583520c-1e89-4aea-8424-56e52d0047ca', 'HAIER HIL2002CSSH:20 LTR CONVECTION', NULL, 'e8df29cf-abd3-4e8d-9718-cb2d3365e860', 'HAIER', 'HIL2002CSSH:20 LTR CONVECTION', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:50:24.811284+05:30', '2026-10-09 18:50:24.811284+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('c1b60d3e-060c-4d67-b0cd-a7c26e405618', 'HAIER HIL2002GBPH:INDIA/HAIER', NULL, 'e8df29cf-abd3-4e8d-9718-cb2d3365e860', 'HAIER', 'HIL2002GBPH:INDIA/HAIER', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:50:24.811284+05:30', '2026-10-09 18:50:24.811284+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('434b9a12-b1bf-4628-92eb-d8c334d06686', 'ROCKWELL GFR 550 DDUC5S', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'GFR 550 DDUC5S', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:00:26.890128+05:30', '2026-10-08 17:00:26.890128+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('79506c87-6018-4ea5-9b28-6462f32ade86', 'ROCKWELL GFR 550 DDUCSS5S', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'GFR 550 DDUCSS5S', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:00:55.19106+05:30', '2026-10-08 17:00:55.19106+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('61a40a62-062d-4108-8e11-969ddd746588', 'HAIER HIL2002MFPH:20L SOLO', NULL, 'e8df29cf-abd3-4e8d-9718-cb2d3365e860', 'HAIER', 'HIL2002MFPH:20L SOLO', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:50:24.811284+05:30', '2026-10-09 18:50:24.811284+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('624eda9f-b424-4273-bb83-c9b8b783ed7b', 'HAIER HIL 20V1 MBPD:MWO', NULL, 'e8df29cf-abd3-4e8d-9718-cb2d3365e860', 'HAIER', 'HIL 20V1 MBPD:MWO', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:50:24.811284+05:30', '2026-10-09 18:50:24.811284+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('67a2e9f1-233d-4ea7-a576-5fc33861d833', 'ROCKWELL RVC 1100', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'RVC 1100', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:02:45.326261+05:30', '2026-10-08 17:02:45.326261+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('35030c4b-f128-4a69-a178-a64919377a72', 'HAIER HIL2301MBEJ:23L/Haier/Solo', NULL, 'e8df29cf-abd3-4e8d-9718-cb2d3365e860', 'HAIER', 'HIL2301MBEJ:23L/Haier/Solo', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:50:24.811284+05:30', '2026-10-09 18:50:24.811284+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('e6b8d9ec-b39b-4b45-b06b-68fc53aa1cde', 'HAIER MWO HIL3001CBSH:IN/HAIER  30 L  CON', NULL, 'e8df29cf-abd3-4e8d-9718-cb2d3365e860', 'HAIER', 'MWO HIL3001CBSH:IN/HAIER  30 L  CON', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:50:24.811284+05:30', '2026-10-09 18:50:24.811284+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('1ccb8e45-c1d5-44d1-b13a-005a31e720b2', 'HAIER HEB-452TS-P:REF/HAIER/445L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HEB-452TS-P:REF/HAIER/445L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('8005f9da-7015-4ba9-9b22-133184b3db93', 'HAIER HEF-253GS-P:REF/HAIER/240L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HEF-253GS-P:REF/HAIER/240L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('368b8ab5-e127-4d5c-93ca-496ac0e2315c', 'HAIER HES-690GK:REF/Haier/596L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HES-690GK:REF/Haier/596L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('f247fea5-ff9f-463b-b02e-7f9bc482e4ad', 'HAIER HRB-2871EMSA-P:REF/HAIER/237L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-2871EMSA-P:REF/HAIER/237L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('42d3fb5d-8f35-4b0b-82c5-bcb4aacd6d48', 'HAIER HRB-2872EKGA-P:REF/HAIER/237L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-2872EKGA-P:REF/HAIER/237L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('15ce6ecf-cf19-44c9-81da-717aa944fac0', 'HAIER HIC-654FCF-O:FFD/', NULL, '414278e1-8d2a-4824-859e-87b8aaffb4a0', 'HAIER', 'HIC-654FCF-O:FFD/', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:48:44.148858+05:30', '2026-10-09 19:10:09.297252+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('8ec9b0fb-4689-4b54-a9a6-7cd10884163a', 'HAIER HIH-G60HM-G:Touch&LED Display', NULL, '414278e1-8d2a-4824-859e-87b8aaffb4a0', 'HAIER', 'HIH-G60HM-G:Touch&LED Display', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:48:44.148858+05:30', '2026-10-09 19:10:17.422178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('67303761-7b54-48c5-8f2a-3898a2a33a48', 'CARRIER AC CARRIER 18K INDUS GXI ALPHA HYBRIDJET 1.5 TON 3*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'CARRIER', 'AC CARRIER 18K INDUS GXI ALPHA HYBRIDJET 1.5 TON 3*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:48:06.262595+05:30', '2026-10-09 17:48:06.262595+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('a2943f0e-4eac-4199-bec0-b45cdb2e2a96', 'CARRIER CARRIER 24K XCEED EDGE GXIINV AC 5*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'CARRIER', 'CARRIER 24K XCEED EDGE GXIINV AC 5*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:49:21.769679+05:30', '2026-10-09 17:49:21.769679+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('90492d3d-ac36-4a1f-bc8f-b9005c976939', 'CARRIER CARRIER AC 24K XCEED EDGE GXI ALPHA HYBRIDJET 3*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'CARRIER', 'CARRIER AC 24K XCEED EDGE GXI ALPHA HYBRIDJET 3*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:49:52.37412+05:30', '2026-10-09 17:49:52.37412+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('63bea063-3723-4969-9d54-24bf1ddb5917', 'GENERAL ASGG 24 CGAA-B 2.0T INV AC 5*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGG 24 CGAA-B 2.0T INV AC 5*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:54:09.133437+05:30', '2026-10-09 17:54:09.133437+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('044e780d-37ab-4bfb-a93f-28d135453547', 'HAIER AC HAIER HS12C-TCS3B 1T 3* (INV)', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'AC HAIER HS12C-TCS3B 1T 3* (INV)', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('bbc8d408-98e5-4e2c-ac47-3d87abdb0b22', 'HAIER HS12V-AOW3BN-INV:AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HS12V-AOW3BN-INV:AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('13d1a500-00c5-4b32-b5b0-e45a43aced97', 'HAIER HS 12V PNW3BN-INV AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HS 12V PNW3BN-INV AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('2619236d-4e53-476f-8a30-2489b22dd25b', 'HAIER HS 13C POW3BN-INV:AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HS 13C POW3BN-INV:AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('83c70fe6-10de-44ae-a2f7-df1341f9958a', 'HAIER HS13E-TXG5B(INV):AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HS13E-TXG5B(INV):AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('894dfc6c-5206-4753-865e-5dbf4cf6d369', 'HAIER HS13K-PYG5BE-INV:AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HS13K-PYG5BE-INV:AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('832428eb-1af6-4b3c-b49d-e65608301e63', 'HAIER HS13K-PZB3BN-INV:AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HS13K-PZB3BN-INV:AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('9b6d99ae-b6dd-4518-ba67-2608c30655d1', 'HAIER HS 18EP-TXS5BN-INV:AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HS 18EP-TXS5BN-INV:AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('e298d87c-cce3-4c23-931c-2031a968a5cc', 'HAIER HS19E-TXW5BN-INV:AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HS19E-TXW5BN-INV:AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('d1a682f7-4aaf-4f85-8dcb-236368d35256', 'HAIER HSI 12VP-S3NB-I:AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HSI 12VP-S3NB-I:AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('305f02d8-7245-499d-a98f-5d95c7a1d8c1', 'HAIER HSI 13VP-G3NB-I:AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HSI 13VP-G3NB-I:AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('2b8908cb-64e9-4b28-abbb-81bddb415f2c', 'HAIER HSI 14EHD-GAI5NB-I:AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HSI 14EHD-GAI5NB-I:AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('381fc5ab-1b66-430f-921a-1ace032eb8c3', 'HAIER HSI 14KU-CAI4NB-I:AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HSI 14KU-CAI4NB-I:AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('a77f1c84-5d51-4bd7-b71e-a6d4c25e53af', 'HAIER HSI 19EHD-GAI5NB-I:AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HSI 19EHD-GAI5NB-I:AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('4f7dd0f2-62e5-4bb8-b2c3-50f6e61e0a2a', 'HAIER HSI 48N-G3NB-I:AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HSI 48N-G3NB-I:AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('366fba52-56dc-45d4-a4dd-68cc63691d8e', 'HAIER HSI 48VP-S3NB-I:AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HSI 48VP-S3NB-I:AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('b0e0bb06-1895-45b3-b2a1-9924e3985fe7', 'HAIER HSI 50CP-S3NB-I:AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'HAIER', 'HSI 50CP-S3NB-I:AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:35:03.742715+05:30', '2026-10-09 18:35:03.742715+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('d3dc8b67-a0ed-436f-965f-013c4f1e9efc', 'HAIER HAF-M403I:PIP', NULL, '360e12f4-e4b9-4a67-9169-290f2ac8dc67', 'HAIER', 'HAF-M403I:PIP', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:36:29.813714+05:30', '2026-10-09 18:37:10.85252+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('c27f679f-759c-4bd6-b0b1-038cd6d5aec2', 'HAIER HAF-D503B:PIP', NULL, '360e12f4-e4b9-4a67-9169-290f2ac8dc67', 'HAIER', 'HAF-D503B:PIP', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:36:29.813714+05:30', '2026-10-09 18:37:29.504476+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('455c98c4-084e-496c-bba5-de96ce483ba6', 'HAIER HW70-IM12929:PUNE', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HW70-IM12929:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('f8b81643-04a8-48b8-928e-41bec408ad68', 'HAIER HW70-IM12929BK:PUNE', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HW70-IM12929BK:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('0a26a1bc-d6ae-4b59-85c7-a2622409e22c', 'HAIER HW90-DM14F9BKU1: PUNE', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HW90-DM14F9BKU1: PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('0cc42ac9-3e11-4609-9075-fbc5e90bf39c', 'ROCKWELL GFR 910 UC5S', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'GFR 910 UC5S', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:01:52.374719+05:30', '2026-10-08 17:01:52.374719+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('4f7e752a-a900-4279-a7f3-bdd59c7e4887', 'ROCKWELL ROCKWELL MB-100', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'ROCKWELL MB-100', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:02:27.009787+05:30', '2026-10-08 17:02:27.009787+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('acb37210-eb8a-4759-b4f0-fb46e2a90e7a', 'ROCKWELL RVC 400', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'RVC 400', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:03:13.350828+05:30', '2026-10-08 17:03:13.350828+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('72aa311b-e0c8-4a6f-8d9e-80c9c5cad30f', 'ROCKWELL RVC 550', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'RVC 550', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:03:59.677214+05:30', '2026-10-08 17:03:59.677214+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('19e91626-5ea1-44ed-be33-252badcd5ef8', 'HAIER HWD120-DM14F11BKU1:PUNE', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HWD120-DM14F11BKU1:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('13cb3ab9-0511-4ab1-afb5-94e92fea8eb2', 'HAIER HWM60-1269DB:PUNE', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HWM60-1269DB:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('22c9eb40-cd49-4fd7-998f-8e4aeda417cc', 'HAIER HWM70-306ES5N1:PUNE', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HWM70-306ES5N1:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('46e4cc77-0020-475c-800b-bb42852228bb', 'HAIER HWM70-306S8:PUNE', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HWM70-306S8:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('8d2b048f-fb53-476e-82e4-caba8d509b76', 'ROCKWELL RVC 700', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'RVC 700', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:04:13.25429+05:30', '2026-10-08 17:04:13.25429+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('d0ed169a-564a-4714-a8cd-c60ab2b11f60', 'HAIER HWM 75-678EBK:PUNE', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HWM 75-678EBK:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('9f004380-8f62-4e6e-94a5-59dfd1b6bed4', 'HAIER HWM75-H678ES5:NOIDA', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HWM75-H678ES5:NOIDA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('2a6fb377-44d5-4b58-9882-6a4e69839104', 'ROCKWELL SFR 250 SDU-4S', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'SFR 250 SDU-4S', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:04:40.124677+05:30', '2026-10-08 17:04:40.124677+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('e005dfbd-c056-416f-8fb9-74067e0a4659', 'ROCKWELL SFR 350 DDU5S', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'SFR 350 DDU5S', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:05:34.143567+05:30', '2026-10-08 17:05:34.143567+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('98c6d742-2bce-4e95-9ba6-daa72bebd5f0', 'ROCKWELL SFR 350GTS LED', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'SFR 350GTS LED', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:06:10.005308+05:30', '2026-10-08 17:06:10.005308+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('7449ebcc-8d69-42c3-8df2-d20a0c37a96c', 'ROCKWELL SFR 450 DDU-5S', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'SFR 450 DDU-5S', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:06:24.958425+05:30', '2026-10-08 17:06:24.958425+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('26eca82c-bd82-4819-a3c9-cab776834bfb', 'ROCKWELL SFR 450 GTS LED', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'SFR 450 GTS LED', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:06:49.050572+05:30', '2026-10-08 17:06:49.050572+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('e5a644d6-54e8-4bbc-b27c-1fca0d8d63cf', 'HAIER HWM75-H826S6:NOIDA', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HWM75-H826S6:NOIDA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('3386cf89-63a0-4692-8a80-c348690fd507', 'HAIER HWM80-310BK:PUNE', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HWM80-310BK:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('612428e9-af95-4df6-ba54-e30dcd58b971', 'HAIER HWM 80-678BK:PUNE', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HWM 80-678BK:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('b6926706-963e-4a39-acd2-f424a4cbbcba', 'HAIER HWM 80-688 S8:NOIDA', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HWM 80-688 S8:NOIDA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('d536fa33-58fa-4f26-8836-a3c10ac12dfe', 'HAIER HWM 80-H320BK:NOIDA', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HWM 80-H320BK:NOIDA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('de820278-fb15-46fb-919e-a5090fab59cf', 'HAIER HWM85-316BK:NOIDA', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HWM85-316BK:NOIDA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('5dfb33bf-2c0a-40c2-a340-448ad9c825d5', 'ROCKWELL SFR 550 DDU5S', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'SFR 550 DDU5S', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:07:04.86483+05:30', '2026-10-08 17:07:04.86483+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('bacc9a8e-8ce2-455f-9166-809aba107dfa', 'ROCKWELL SFR 750 TDU5S', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'SFR 750 TDU5S', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:08:46.137962+05:30', '2026-10-08 17:08:46.137962+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('0fd5dc56-f051-441c-a32f-031aa85c4438', 'ROCKWELL GFR 910 UC5S', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'ROCKWELL', 'GFR 910 UC5S', NULL, 'piece', true, NULL, 0, 0, false, false, '2026-10-08 17:01:12.983859+05:30', '2026-10-08 17:12:18.722915+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('b98ff282-df28-4a8b-962f-0da93398777c', 'GENERAL 12CGWA-B 1.0T INV AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', '12CGWA-B 1.0T INV AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:13:23.323547+05:30', '2026-10-08 17:13:23.323547+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('3f5872a1-df35-4bf7-85b4-22cc53085f79', 'GENERAL ASGA 18 BMAA-B 1.5T Split Ac', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGA 18 BMAA-B 1.5T Split Ac', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:13:51.763891+05:30', '2026-10-08 17:13:51.763891+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('8811c429-0cf7-477f-ada4-18fdaa1beee1', 'GENERAL ASGA18BUTA-B', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGA18BUTA-B', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:14:29.48848+05:30', '2026-10-08 17:14:29.48848+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('43fd84b0-ee86-4411-9d4c-0a0ac31959af', 'GENERAL ASGA 24 BMAA-B 2.0T Split Ac', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGA 24 BMAA-B 2.0T Split Ac', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:14:09.64954+05:30', '2026-10-08 17:14:46.283152+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('09582965-46f7-4019-bba0-7161ec1cfeb3', 'GENERAL ASGA24BUTA-B 2T', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGA24BUTA-B 2T', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:15:02.38574+05:30', '2026-10-08 17:15:02.38574+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('03aca04a-fcf1-4708-bbac-074130fc2c0f', 'GENERAL ASGG 12CGAB-B 1T INV AC', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGG 12CGAB-B 1T INV AC', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:15:32.1243+05:30', '2026-10-08 17:15:32.1243+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('2466d044-b519-4a59-92f5-67a261d23b44', 'GENERAL ASGG 12 CGTB   1 Tn 5*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGG 12 CGTB   1 Tn 5*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:16:00.841635+05:30', '2026-10-08 17:16:00.841635+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('f306cbd1-f4fb-45e2-b408-ab8cb46e536b', 'GENERAL ASGG12CGWA-B 1 T INV AC 4*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGG12CGWA-B 1 T INV AC 4*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:16:18.57077+05:30', '2026-10-08 17:16:18.57077+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('953f64bb-183a-4dcc-ad51-4a9b8d1ba754', 'GENERAL ASGG 12 CKWA-B 1.OT INV AC 3*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGG 12 CKWA-B 1.OT INV AC 3*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:16:40.348617+05:30', '2026-10-08 17:16:40.348617+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('06521486-9173-4469-a926-09fdde8f7fba', 'GENERAL ASGG 12 CPWA-B 1T INV AC3*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGG 12 CPWA-B 1T INV AC3*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:17:23.484745+05:30', '2026-10-08 17:17:23.484745+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('03316b63-3179-42e1-9210-df9a792649a9', 'GENERAL ASGG 18 CEAC-B 1.5T INC AC 5*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGG 18 CEAC-B 1.5T INC AC 5*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:17:40.86429+05:30', '2026-10-08 17:17:40.86429+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('a644739a-efcc-47fb-8117-bcfc36c4b41e', 'GENERAL ASGG 18 CETB-B 1.5T INV AC 5*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGG 18 CETB-B 1.5T INV AC 5*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-08 17:18:02.716345+05:30', '2026-10-08 17:18:02.716345+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('4958f751-6916-45fc-8725-d0bf223ac9c9', 'FORMENTY LED FMTY FM32HDSQTVDXB1 Google Q Led VELORA', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'FORMENTY', 'LED FMTY FM32HDSQTVDXB1 Google Q Led VELORA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 11:32:19.460036+05:30', '2026-10-09 11:32:19.460036+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('730cc975-b1e6-48b6-94dc-8f5686b98c7a', 'FORMENTY LED FMTY -FM32HDSQTVWWCR GOOGLE Q LED TV -Cinara', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'FORMENTY', 'LED FMTY -FM32HDSQTVWWCR GOOGLE Q LED TV -Cinara', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 11:32:31.151671+05:30', '2026-10-09 11:32:31.151671+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('9ab2a8e4-e693-47f2-9024-c1a791556c8f', 'FORMENTY LED FMTY FM40FDSQTVDXB2 Google Q Led VELORA', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'FORMENTY', 'LED FMTY FM40FDSQTVDXB2 Google Q Led VELORA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 11:33:14.210849+05:30', '2026-10-09 11:33:14.210849+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('73cfffaa-0a4c-4841-8df0-9a5a9393b343', 'FORMENTY LED FMTY FM43UHDQTVDXB4 4K UHD Q LED VELORA', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'FORMENTY', 'LED FMTY FM43UHDQTVDXB4 4K UHD Q LED VELORA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 11:33:47.619372+05:30', '2026-10-09 11:33:47.619372+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('8590701f-97f0-486e-9b47-ced013bd4c1d', 'FORMENTY FM32HDSQSPR1DX Q LED-SPECTRA SERIES', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'FORMENTY', 'FM32HDSQSPR1DX Q LED-SPECTRA SERIES', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 11:30:41.699172+05:30', '2026-10-09 15:03:17.648094+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('8531cbb7-5457-49c3-9e0d-4529700e42bf', 'FORMENTY FM55UHDQSPR5DX Q LED- SPECTRA SERIES', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'FORMENTY', 'FM55UHDQSPR5DX Q LED- SPECTRA SERIES', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 11:31:11.920615+05:30', '2026-10-09 13:40:00.804401+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('7999322a-f1bb-4a0f-a72e-475b819b6a3f', 'FORMENTY FM43UHDQSPR4DX QLED-SPECTRA SERIES', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'FORMENTY', 'FM43UHDQSPR4DX QLED-SPECTRA SERIES', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 11:30:57.553489+05:30', '2026-10-09 16:40:49.482871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('00d31b1c-02fe-454f-ad9c-3bd47c74f7d0', 'FORMENTY LED FMTY FM32HDTVDXB1 GOOGLE  QLED TV VELORA', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'FORMENTY', 'LED FMTY FM32HDTVDXB1 GOOGLE  QLED TV VELORA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 11:32:54.063222+05:30', '2026-10-09 15:51:33.436686+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('f1405e84-41dc-4b22-bd87-bd9006a17c81', 'FORMENTY FM 32 HDSPT2 SMART', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'FORMENTY', 'FM 32 HDSPT2 SMART', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 11:30:14.054387+05:30', '2026-10-09 15:51:33.436686+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('75b4ac90-2d54-4c52-aaae-1c86b6554ae8', 'FORMENTY FM32HDSPB2YU LED- LUMINOR SERIES', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'FORMENTY', 'FM32HDSPB2YU LED- LUMINOR SERIES', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 11:30:01.806721+05:30', '2026-10-09 15:51:33.436686+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('0dd497cc-caf0-4134-9437-535b16365a0b', 'FORMENTY FM 32 HDRPT1', NULL, '043d664f-f89e-4187-99f0-ff9bceb2575c', 'FORMENTY', 'FM 32 HDRPT1', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 11:29:46.017984+05:30', '2026-10-09 16:40:49.482871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('b837c539-50a3-4150-9fe9-919c841edc00', 'CARRIER AC CARRIER 19K EXCEED LUMO GXI 1.5 T 5*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'CARRIER', 'AC CARRIER 19K EXCEED LUMO GXI 1.5 T 5*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:48:32.256582+05:30', '2026-10-09 17:48:32.256582+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('fa8b239a-c9e1-43d7-bf5d-37c9e0a3d0dc', 'GENERAL ECCGA4 EXTENDED COMPREHNSIVE COVER(F/I/C)4YR', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ECCGA4 EXTENDED COMPREHNSIVE COVER(F/I/C)4YR', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:52:48.561338+05:30', '2026-10-09 17:52:48.561338+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('ea453d9a-85fb-4293-b1cc-2cabf84cd453', 'GENERAL ASGG30CEAC.B 2.5 T INV AC 5*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGG30CEAC.B 2.5 T INV AC 5*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:53:30.112812+05:30', '2026-10-09 17:53:30.112812+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('7100a1c9-9c26-447b-b802-c50f699ef157', 'GENERAL ASGG 24CEAC-B 2T INV AC 5*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGG 24CEAC-B 2T INV AC 5*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:54:22.402935+05:30', '2026-10-09 17:54:22.402935+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('15b44915-d3de-434f-b570-e4e605161410', 'GENERAL ASGG 18 CNWA-B 1.5T INV AC 3*', NULL, 'a61627a9-d0a7-49b8-af5f-56c872026561', 'GENERAL', 'ASGG 18 CNWA-B 1.5T INV AC 3*', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 17:56:02.364721+05:30', '2026-10-09 17:56:02.364721+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('73420d0c-0bc5-44c9-b156-ddaf3e83440a', 'HAIER HWM90-H688BK:NOIDA', NULL, 'd690ccfe-6e58-4055-a200-3ea07d4134b3', 'HAIER', 'HWM90-H688BK:NOIDA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:18.963178+05:30', '2026-10-09 18:46:18.963178+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('00e9b551-e68a-4da7-aa0f-cdd60e73332a', 'HAIER HFC-230SPW4:HTDF/HAIER', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'HAIER', 'HFC-230SPW4:HTDF/HAIER', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:41.488497+05:30', '2026-10-09 18:46:41.488497+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('989e17d3-4e4a-4380-a138-eb386923ff2c', 'HAIER HFC-300GM5:GT DF/HAIER', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'HAIER', 'HFC-300GM5:GT DF/HAIER', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:41.488497+05:30', '2026-10-09 18:46:41.488497+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('6427e27b-c8d4-44e9-b150-e899dfb2a51f', 'HAIER HFC-400GM5:GT DF/HAIER', NULL, '5d3395d9-808e-4fff-815c-a0facdf8bbdb', 'HAIER', 'HFC-400GM5:GT DF/HAIER', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:46:41.488497+05:30', '2026-10-09 18:46:41.488497+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('c0a76d7f-cb88-48b0-90b0-df316775dc4f', 'HAIER HRB-2872EMGA-P REF/Haier/237L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-2872EMGA-P REF/Haier/237L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('40bd5ac9-86e1-48cd-bf1f-b420b7785fe2', 'HAIER HRB-3152 PKGA-P:REF/HAIER/265L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-3152 PKGA-P:REF/HAIER/265L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('fe980e52-ba3b-43af-9d06-82cf690ffba7', 'HAIER HRB-3152PKG-P', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-3152PKG-P', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('5da6d1bb-42a5-486c-aa6c-cc0eb58570c4', 'HAIER HRB-3501BS-P:REF/Haier/300L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-3501BS-P:REF/Haier/300L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('eaf8c56a-23ff-4c4a-899e-d0971dfbab90', 'HAIER HRB-3752BGKA-P:REF/Haier/325L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-3752BGKA-P:REF/Haier/325L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('bad9fba9-ab89-494c-b6b0-b0c98e327617', 'HAIER HRB-3752PKGA-P:REF/HAIER/325L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-3752PKGA-P:REF/HAIER/325L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('2b28aede-861a-49af-b62c-d93065ae2b83', 'HAIER HRB-3752PMGA-P:REF/Haier/325L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-3752PMGA-P:REF/Haier/325L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('34098d38-ae9d-4061-b074-c5ac8e5ee342', 'HAIER HRB-4052PKGA-P:REF/HAIER/355L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-4052PKGA-P:REF/HAIER/355L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('a8d4fe8f-3e94-41eb-897c-e60c309be8f5', 'HAIER HRB-4052PMGA-P:REF/HAIER/355L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-4052PMGA-P:REF/HAIER/355L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('57d81821-8a35-4fcd-9759-5f56478c89f1', 'HAIER HRB-4053PKG-P:REF/HAIER/355L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-4053PKG-P:REF/HAIER/355L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('fdb8722f-1046-4bf0-aba5-5b88e0638e0e', 'HAIER HRB-4952BIS-P:REF/HAIER/445L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-4952BIS-P:REF/HAIER/445L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('ae5e1994-119d-408d-ba94-d655112ab006', 'HAIER HRB-4952CKGA-P:REF/HAIER/445L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-4952CKGA-P:REF/HAIER/445L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('79e5809e-dff6-43b3-9095-acc72ffaa698', 'HAIER HRB-600IS:REF/Haier/520L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-600IS:REF/Haier/520L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('29ce2c96-1096-4c85-a3e3-d30b3939d436', 'HAIER HRB-700KGU1:REF/Haier/630L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRB-700KGU1:REF/Haier/630L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('e36d6751-d9b0-46de-bfd2-dcd979f4faf5', 'HAIER HRF-2901EMSA-P:REF/Haier/240L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRF-2901EMSA-P:REF/Haier/240L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('090a15be-19d8-473a-b4e1-8a98dfba95c4', 'HAIER HRF-2901 IERBA-P:REF/HAIER/240L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRF-2901 IERBA-P:REF/HAIER/240L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('edf4a7de-7bed-4e95-9449-8c15c87cf092', 'HAIER HRF-2902EKGA-P:REF/Haier/240L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRF-2902EKGA-P:REF/Haier/240L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('73ac6648-081c-4950-997d-0363511f8fa3', 'HAIER HRF-2902 EWGA-P:REF/HAIER/240L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRF-2902 EWGA-P:REF/HAIER/240L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('c70eb5be-4aed-4246-bf79-9b6e3cd68930', 'HAIER HRF-2902 IEMSA-P:REF/Haier/240L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRF-2902 IEMSA-P:REF/Haier/240L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('bb45eec1-ecbc-4eb6-8f66-81eb5404a01b', 'HAIER HRF-2902IERBA-P:REF/Haier/240L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRF-2902IERBA-P:REF/Haier/240L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('44332888-3dd1-4018-a421-0bdb9b796941', 'HAIER HRF-3182EIS-P:REF/Haier/268L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRF-3182EIS-P:REF/Haier/268L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('0abdc611-5b28-429e-9bb0-5531949d2849', 'HAIER HRF-3182PKGA-P:REF/HAIER/268L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRF-3182PKGA-P:REF/HAIER/268L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('019c402c-7b78-42e7-b081-a435da5d1169', 'HAIER HRF-3782PLKGA-P:REF/HAIER/328L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRF-3782PLKGA-P:REF/HAIER/328L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('c01d0089-cee7-4639-85dc-c8283230a622', 'HAIER HRF-4083BIS-P:REF/HAIER/358L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRF-4083BIS-P:REF/HAIER/358L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('f130bd40-abe3-4fe3-8b6b-edb6eceafcbe', 'HAIER HRF-4083PLKG-P:REF/Haier/358L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRF-4083PLKG-P:REF/Haier/358L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('6c44b74d-2d52-4e07-aee5-d1cc0622c852', 'HAIER HRF-5252BGK-N:REF/HAIER/475L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRF-5252BGK-N:REF/HAIER/475L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('290c8b5a-79c7-4a7c-ad75-8f504dc540b9', 'HAIER HRS-615FS:REF/HAIER/540L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRS-615FS:REF/HAIER/540L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('844fa6ca-ca9d-40c5-b605-245ab3d259a6', 'HAIER HRS-682SS:REF/Haier/602 L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRS-682SS:REF/Haier/602 L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('6d021510-815c-4e78-98c2-2feb18325a09', 'HAIER HRT-683GOG-P:REF/Haier/598L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRT-683GOG-P:REF/Haier/598L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('4b78f6a6-283b-451e-9c8d-334a22ab7a34', 'HAIER HRD-1861BBR-N:REF/Haier/165L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRD-1861BBR-N:REF/Haier/165L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('5ebfb4b7-3cb1-4b4e-bd5b-43a7303ee93f', 'HAIER HRD-1953CRC:REF/Haier/195L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRD-1953CRC:REF/Haier/195L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('9a8b576d-b829-4f32-ab3e-b78d48b1483c', 'HAIER HRD-2052BBR-P:REF/HAIER/185L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRD-2052BBR-P:REF/HAIER/185L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('a18f605f-40e0-44ed-999d-42bf1af943a5', 'HAIER HRD-2101 BBRA-P:REF/HAIER/190L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRD-2101 BBRA-P:REF/HAIER/190L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('9ffc4921-adb7-4696-99dc-a848c201ef1a', 'HAIER HRD-2101BBR-P:REF/Haier/190L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRD-2101BBR-P:REF/Haier/190L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('28bfbcd8-35fb-4a62-9a3c-a360e52ce4f5', 'HAIER HRD-2103CBS-P:REF/HAIER/190L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRD-2103CBS-P:REF/HAIER/190L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('d7f5d60e-a13d-4a3f-b1ef-f6ca09914d66', 'HAIER HRD-2105BNS-P:REF/Haier/190L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRD-2105BNS-P:REF/Haier/190L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('7d8ea39b-775e-4d2a-bcea-1ae18bbfe9ea', 'HAIER HRD-2105CBSA-P:REF/Haier/190L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRD-2105CBSA-P:REF/Haier/190L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('89b3cadf-3840-4aaf-b245-d1f4b011923a', 'HAIER HRD-2261SMMA-N:REF/HAIER/205L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRD-2261SMMA-N:REF/HAIER/205L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('166d3b05-e16d-493d-b0f1-5dbdde83d325', 'HAIER HRD-2261SPMA-N:REF/HAIER/205L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRD-2261SPMA-N:REF/HAIER/205L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('d0b0d629-24e2-4149-aab2-8247096ee1b9', 'HAIER HRD-2261SRMA-N:REF/HAIER/205L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRD-2261SRMA-N:REF/HAIER/205L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('8c820db5-ce58-4a67-a5fa-546b07eaac24', 'HAIER HRD-2561SGSA-N:REF/HAIER/235L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRD-2561SGSA-N:REF/HAIER/235L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('4ce1c2cb-f1fc-40fc-b620-c2b8fce9fa89', 'HAIER HRD-752KSA-MINIBAR/HAIER/50L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'HRD-752KSA-MINIBAR/HAIER/50L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('087b61ab-e2bf-4418-8904-bb3279bd020a', 'HAIER REF HAIER HRD 2115PMGA-N:REF/HAIER/190L', NULL, '3866bb27-b9b4-40c1-99b8-2aed06198a18', 'HAIER', 'REF HAIER HRD 2115PMGA-N:REF/HAIER/190L', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:52:24.088871+05:30', '2026-10-09 18:52:24.088871+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('af4b107b-a497-41a9-b712-cabe548a3efa', 'HAIER Civic X11 :Robot Vacum Cleaner', NULL, '3e8eaf81-f945-4859-aceb-b65565116494', 'HAIER', 'Civic X11 :Robot Vacum Cleaner', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:53:12.46363+05:30', '2026-10-09 18:53:12.46363+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('4a38f626-3d2b-4169-a2c6-4b8a0a8210c2', 'HAIER Civic X11 Pro:Robot Vacum Cleaner', NULL, '3e8eaf81-f945-4859-aceb-b65565116494', 'HAIER', 'Civic X11 Pro:Robot Vacum Cleaner', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:53:12.46363+05:30', '2026-10-09 18:53:12.46363+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('53c7284a-9818-4e53-ba50-4e2dcb457c6d', 'HAIER PRObotDTX/ROBVAC/LDS Vaccum Cleaner', NULL, '3e8eaf81-f945-4859-aceb-b65565116494', 'HAIER', 'PRObotDTX/ROBVAC/LDS Vaccum Cleaner', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:53:12.46363+05:30', '2026-10-09 18:53:12.46363+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('4b860ac6-56ae-4436-8b36-7879f372e245', 'HAIER TH27U1:HR/T/WHITE Vaccum Cleaner', NULL, '3e8eaf81-f945-4859-aceb-b65565116494', 'HAIER', 'TH27U1:HR/T/WHITE Vaccum Cleaner', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:53:12.46363+05:30', '2026-10-09 18:53:12.46363+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('d02f27ce-8ced-49a0-bc56-cc019d184640', 'HAIER HVC-1050GHC:HIL/DF', NULL, '1fc15e19-a356-47e2-b5ff-57183448f844', 'HAIER', 'HVC-1050GHC:HIL/DF', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:53:48.510399+05:30', '2026-10-09 18:53:48.510399+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('a7403310-b721-4071-be06-8c2d9a019371', 'HAIER HVC-305GT5:VISI COOLER/GLASS DOOR', NULL, '1fc15e19-a356-47e2-b5ff-57183448f844', 'HAIER', 'HVC-305GT5:VISI COOLER/GLASS DOOR', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:53:48.510399+05:30', '2026-10-09 18:53:48.510399+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('19b372ac-62b6-4ed6-8950-1231ca814e6d', 'HAIER HVC-405GT5:VISI COOLER/GLASS DOOR', NULL, '1fc15e19-a356-47e2-b5ff-57183448f844', 'HAIER', 'HVC-405GT5:VISI COOLER/GLASS DOOR', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:53:48.510399+05:30', '2026-10-09 18:53:48.510399+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('a17bd8cf-d181-431a-adcb-816568acb7ff', 'HAIER HVC-505GT5:VISI COOLER/GLASS DOOR', NULL, '1fc15e19-a356-47e2-b5ff-57183448f844', 'HAIER', 'HVC-505GT5:VISI COOLER/GLASS DOOR', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:53:48.510399+05:30', '2026-10-09 18:53:48.510399+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('94784edd-0fd3-4cc8-b9ba-d561d2e318e9', 'HAIER EI3V-ZYON 3kw(I):W/H', NULL, '7b507da6-509e-4af1-91a9-c9a827c4f2b3', 'HAIER', 'EI3V-ZYON 3kw(I):W/H', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:54:27.356299+05:30', '2026-10-09 18:54:27.356299+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('bb5bc50c-f6ac-49b8-b9be-b5a66af4d9cf', 'HAIER ES10V-PRECIS:ES10V-PRECIS', NULL, '7b507da6-509e-4af1-91a9-c9a827c4f2b3', 'HAIER', 'ES10V-PRECIS:ES10V-PRECIS', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:54:27.356299+05:30', '2026-10-09 18:54:27.356299+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('c7e9ac7f-4d0d-4fe8-bada-ef2617c01ec2', 'HAIER ES10V-VL:ES10V-VL', NULL, '7b507da6-509e-4af1-91a9-c9a827c4f2b3', 'HAIER', 'ES10V-VL:ES10V-VL', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:54:27.356299+05:30', '2026-10-09 18:54:27.356299+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('8abf1161-d05b-41ec-896a-06755352a4e0', 'HAIER WH HAIER ES 6V-Q1(H)', NULL, '7b507da6-509e-4af1-91a9-c9a827c4f2b3', 'HAIER', 'WH HAIER ES 6V-Q1(H)', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:54:27.356299+05:30', '2026-10-09 18:54:27.356299+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('4bee8f4a-f9e8-4134-ac2b-b0409ec3ac6f', 'HAIER HWD-3WTT:HIL/WD', NULL, '29b08f28-6149-437c-8a16-80fb4186bb28', 'HAIER', 'HWD-3WTT:HIL/WD', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:54:59.87+05:30', '2026-10-09 18:54:59.87+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('0c2c6f8e-0df2-4c22-9cfd-07d96ebdb121', 'HAIER HTW100-196BK', NULL, 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'HAIER', 'HTW100-196BK', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:55:39.4624+05:30', '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('b433043e-b2b0-4bd6-b2fe-b625c3a05b72', 'HAIER HTW 120-178BK:NOIDA', NULL, 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'HAIER', 'HTW 120-178BK:NOIDA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:55:39.4624+05:30', '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('aa28789d-a6e2-4b92-9a88-ad459ffe9668', 'HAIER HTW 120-196BK:NOIDA', NULL, 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'HAIER', 'HTW 120-196BK:NOIDA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:55:39.4624+05:30', '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('7d96b565-697a-4403-8a49-2c3481b9096e', 'HAIER HTW140-178BK:NOIDA', NULL, 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'HAIER', 'HTW140-178BK:NOIDA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:55:39.4624+05:30', '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('80b5223b-d367-49ae-88f5-0da611728b42', 'HAIER HTW70-178BKN:NOIDA', NULL, 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'HAIER', 'HTW70-178BKN:NOIDA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:55:39.4624+05:30', '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('011e0f33-6c40-4fed-8e34-c334adc0c4ae', 'HAIER HTW70-178N:PUNE', NULL, 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'HAIER', 'HTW70-178N:PUNE', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:55:39.4624+05:30', '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('f7929e70-ca78-4fe1-a494-9ffe32b3eba7', 'HAIER HTW75-178BBK', NULL, 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'HAIER', 'HTW75-178BBK', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:55:39.4624+05:30', '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('343d507c-86da-4e24-97cd-94ed5863bb79', 'HAIER HTW80-178:NOIDA', NULL, 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'HAIER', 'HTW80-178:NOIDA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:55:39.4624+05:30', '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('e3117194-84fd-40ce-857e-5afb762c933b', 'HAIER HTW85-178BBKN:NOIDA', NULL, 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'HAIER', 'HTW85-178BBKN:NOIDA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:55:39.4624+05:30', '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('2efd17f1-2c91-4cfe-9651-37d3893250a2', 'HAIER HTW85-178BKN1', NULL, 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'HAIER', 'HTW85-178BKN1', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:55:39.4624+05:30', '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('b5995b8f-898b-4866-81ba-c843f4c96f2d', 'HAIER HTW85-178FL:NOIDA', NULL, 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'HAIER', 'HTW85-178FL:NOIDA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:55:39.4624+05:30', '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('a7c82f53-17aa-4a2d-9590-ad2740240d35', 'HAIER HTW85-178 Noida', NULL, 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'HAIER', 'HTW85-178 Noida', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:55:39.4624+05:30', '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('3ba086a5-8eb9-4038-bf74-8f6c60baeabd', 'HAIER HTW85-178PBK', NULL, 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'HAIER', 'HTW85-178PBK', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:55:39.4624+05:30', '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('566cdd21-9e2c-464a-a588-5f9565550202', 'HAIER HTW90-196BBK:NOIDA', NULL, 'c0f349e1-9209-422e-b304-a5f3d0bbf5b8', 'HAIER', 'HTW90-196BBK:NOIDA', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:55:39.4624+05:30', '2026-10-09 18:55:39.4624+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('dd75fa8a-769f-4088-a01a-8557868b6bcd', 'HAIER HIC-653FCF-O:FFD/', NULL, '414278e1-8d2a-4824-859e-87b8aaffb4a0', 'HAIER', 'HIC-653FCF-O:FFD/', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:48:44.148858+05:30', '2026-10-09 19:10:06.309896+05:30');
INSERT INTO public.products (id, name, sku, category_id, brand, model, size_capacity, unit, serial_number_required, description, opening_stock_qty, current_stock_qty, has_had_inward, is_active, created_at, updated_at) VALUES ('eeb482ba-1285-4e93-aea0-669996f9e157', 'HAIER HIC-Q27326-IN:ODM', NULL, '414278e1-8d2a-4824-859e-87b8aaffb4a0', 'HAIER', 'HIC-Q27326-IN:ODM', NULL, 'piece', true, NULL, 0, 0, false, true, '2026-10-09 18:48:44.148858+05:30', '2026-10-09 19:10:13.623054+05:30');


--
-- Data for Name: returns; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: serial_history; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: serial_numbers; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: shops; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('170c0665-2fea-42e9-83b1-c0942ab66a8e', 'ANAS HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('78f3422e-c1f3-488f-91c3-2ae5cf10fcfb', 'BENZY HOSPITALS PRIVATE LIMITED', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('147d17e4-c442-45bd-8ed6-eb8bfdd1afda', 'DR.DOOR', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e973e4d6-e6ec-46a6-a6c5-2247c8474297', 'EVERCOOL ENTERPRISES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e133a516-2da2-488a-8a73-3d20ae874a6e', 'FRIENDS COMPUTERS HOME APPLAINCES & SECURITY SYSTEM', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('215d8e77-13dc-45c8-9fea-6e42f318f86f', 'GODS OWN', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e78df0a1-ff06-4562-8480-9324b4f44386', 'GRAND HOME APPLIANCE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('33b85381-ee77-4af2-9454-6aae310142be', 'HAYATH MEDICAL CENTRE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c5ee6306-87df-40d5-8974-03d085dd41e7', 'HELAN DIGITAL MART', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('961e0a25-5b93-4e94-b9ed-5e896865856a', 'KADOOR ELECTRONICS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('52cb131c-127f-46b4-9d07-0c764fad7979', 'KALPAKA ELECTRONICS (FRK)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('4105f325-5167-4662-85b7-52c87ca9d471', 'KALPAKA ELECTRONICS & HOME BAZAR', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('651e2eee-b386-4421-8297-9227d47782e5', 'Kalpaka Electronics & Home Bazar Mlp', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('1b1a6fa4-1f01-45e0-bb79-fce43eec0d79', 'Kannankandy Fridge centre', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d9a3ef12-1788-479b-8c23-e591a9bb5f64', 'KASIM KUMMALI ADV', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('41a1bd48-9dde-4bf1-a883-a11aec87bdff', 'KERALA FLIGHT ACADEMY PRIVATE LIMITED', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5542eea8-9927-4753-af7d-592367c35a1a', 'MAB TECH EQUIPMENT PRIVATE LIMITED(New)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('2e5f2871-e503-4551-9b72-7c024e878790', 'Mandhi Palce', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('9395b0c0-9eee-476d-bf15-f1ad038ea120', 'MANSOOR PATTAMBI', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('a5e9d1e0-ca2e-464b-be64-ba0657462f1e', 'MERRY SOUL ENTERPRISE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('51684061-ef0c-4945-ba57-bfcd172534e8', 'Mr YESHUDAS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('942f9953-35ad-47fc-b578-116467a9da39', 'MUJEEB ARIMBRA', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('8c45386f-9515-4c7b-a7d3-b9400e8ca04e', 'NESTO HYPER MARKET (CLT)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('99ecb4b9-93ff-455a-aa4a-63b83c102b87', 'NEW TECH COOLING SOLUTIONS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5183fb8b-ff36-42b3-ae92-5f2406a411f5', 'NEW WHITE HOME', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('3ee43a8a-5ce2-4ac1-bbc4-11a7d817c1dd', 'OMEGA AGENCIES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('bd87ed0b-4421-443f-9738-11e2938b112a', 'PRAKASH TRADERS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('ca9def0b-53f2-4877-8da6-08a8734f56f5', 'PV STORE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('02261124-4b60-45d2-88ed-b352a3e53782', 'PV STORE EKKAPPARAMBU', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b8902189-720b-488a-a69e-e39f8cb776c0', 'REAL AGENCY', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('0bb53a80-ef53-4ffd-a3f2-0e66722f75a0', 'RETAIL BILL', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('bc506a19-54ba-4591-a790-072ecb025d3a', 'RIYAS ROK', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('da6afebb-a34e-4130-acbb-ad549dc39797', 'SHAMEER PANDI', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d599b94b-56bc-4817-98f7-ea68f10192cb', 'SIGMA ELECTRONICS MANJERI', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('48bbd731-0af1-4d39-bd80-34edcd586451', 'SMART HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c80d3ae4-80f0-4f41-bbc7-dcf703b2fbc9', 'S.P TRADERS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('0988fa72-e24a-4a06-85f2-dca3633d8338', 'VAVA FURNITURE AND HOME APPLIANCES(New)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d0388df3-a68a-4386-8b89-68b7ad618b6d', 'VK GROUP', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('13182244-6bf1-46f8-b9d7-aa5668c96474', 'AKAM  HOME APPLIANCES & MOBILES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('91d8d12b-9d9c-41cb-9e66-26994ea2f391', 'A K M STORE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('cd8e88d6-c542-4cc4-b198-077ba84517bd', 'ASHIKH ELECTRONIC AND HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c1168439-f218-495e-b5e7-faf41a7fd7b4', 'Brand House Agencies', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('286c740c-6798-4171-b348-e9aa009c9bbf', 'BROTHERS HOME APPLAINES & FURNITURE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('9b6124d1-1db2-4f4b-8af3-fdfde5376f8c', 'BUDGET FURNITURE & HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('49a7ce98-4b80-4365-83ac-af541523136b', 'BUDGET FURNITURE & HOME APPLIANCES (PNKD)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('628c3501-0a7e-4e9e-bec3-6eaada3be7dd', 'CHOICE HOME SERVICES (Mtvlr)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('8e31ca61-2413-4a9a-aef6-3cd78bb51365', 'Cool India Home Needs & Appliances', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('9200f890-cb62-4e9c-830b-deb2616c7112', 'Cool Makers', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5d15aab7-2243-4b14-9f55-e3e005a3e794', 'DIGITAL MART', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('226aa1ff-d73d-474b-933a-954919a2d72b', 'Digital Mart (Kvnr)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('6fc8ac8b-53f5-425e-97df-97cfd6babebc', 'Dream Digital', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('acc58f7c-5bb7-43ea-a182-4ac94793a4c2', 'ELECTRO WORLD FRIDGE HOUSE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b76069a5-19d2-4f23-8e01-a14b13e6507e', 'ELITE METALS & HOME NEEDS  MJRY', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('eb77f472-76c4-473c-8df4-1b254ce209b4', 'E MAX DIGITAL', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b7f69469-7b51-405a-ae5a-800b94c3dfef', 'E WORLD Home Appliances(New)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('cf11c47f-bb0d-4853-b791-44a2a6cce1a5', 'FAMILY HOMELAND ELECTRICALS & SANITARY', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5e3b7195-1858-4a15-8e27-2ecf40d1efad', 'FAMILY METALS & FURNITURE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5c3c51b1-9e93-46ba-9008-ef6837c4d151', 'FOCUS FURNITURE & ELECTRONICS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('663f7392-6b62-4bc8-824b-f7d5c28c1de2', 'FRIDGE HOUSE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e61aaa32-135e-4bfa-8567-994fe792952e', 'GK ENTERPRISES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('82e32476-a919-498c-873e-b9d01dfd5424', 'HAPPY HOME', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c97c85f6-ea96-4191-8a53-547a778e3e56', 'Happy Home Hardware & Electricals', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('daae6f0a-f360-47f8-b744-79d3c6c40dbb', 'HI MART HYPERMARKET', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('1e5828e8-267b-494d-bcd6-537563802d72', 'HOME CHOICE WNDR', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('eb2a2c34-1dcb-4c32-b85c-caa2a4ba372b', 'HOME Q DIGITAL ELECTRONICS& HOME', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('7b9faec4-d2c9-46bd-b276-b10fbdf0eb7b', 'HOMY SMART HOME', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('28a098be-827f-4ed9-aa01-a9de1d99ba76', 'J J KOCHUKUDIYIL', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('803c16a2-7eef-4db3-9ff1-8ca2eb133823', 'Kaippally Home Appliances', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('1ceaddba-3435-41f3-8d39-604cb20091d6', 'KALYANI E MART (New)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('3723884f-2b3a-4bc3-8140-b62ebdf89a7b', 'K C APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d0fe4a78-8d59-4e3b-9cbb-e969b7d8b42a', 'KISWAH HOME GUIDE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('a46422e8-eb89-4b1f-aac1-49894d0b13bf', 'KOCHUKUDIYIL AGENCIES NILAMBUR', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e646ae29-f3e0-49cd-8594-8d42492cd5d8', 'KOCHUS GALLERY', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('9d4bfd67-1e6f-4035-8528-a0d2a78a36ff', 'KODUVALI FURNITURE (New)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d9b0ab81-a6e9-4b65-aff3-cd0d440d203e', 'Koduvally Furniture', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('af10cfda-b3e1-4a54-8689-f2d575591d60', 'KOLAR MILL STORES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c55962fc-fbe9-4f2b-8804-ed398938595b', 'KRIPA HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e0a8e43b-eb7f-4839-899f-37d43b566e32', 'KURIKKAL AGENCIES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('746d23a9-fb20-47ae-8f06-41ed2728f509', 'Lavanya''s Hyper Shoppe', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('39a406cb-6691-460f-9447-368f71e0330d', 'LAVANYA E PLAZA', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('7a384d7f-1013-4678-91d7-cfa1fa742044', 'MADATHIL METALS AND HOME NEEDS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('6626c9c2-1990-4133-8fd8-540b6819666b', 'MANGO DIGI-HUB', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('3c1ab308-a9ce-47d4-b4e3-916ab6ad1cf3', 'MARVEL  APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e6810a9b-6f97-4386-b8c8-9a009f576054', 'MP MART LLP', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e5b33484-3ea5-402d-a9e7-041e6b968775', 'NAMBOOTHIRI`S', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('337e4c21-d0d5-4195-88b5-0c812a504b9b', 'Nero Cold (Ktpdm)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('a2b57457-da3d-4e09-9799-f5e60e5cdee4', 'NERO COLD LLP', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d35af958-d089-4fed-8576-231e48b7e168', 'Nero Cold (New)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('202c9ec3-d912-4862-b79c-4d8b65f8a515', 'NEW KOCHUKUDIYIL AGENCIES KKV', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f5c37a5f-ce5d-4650-8dbb-5bf2d246a72e', 'NEW WAY CENTRE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('a540cb60-8d9d-4ce6-b43e-72b596f4315e', 'PALLISSERY HOME NEEDS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('7846e503-c907-4dd8-a5e1-b4e077d5120e', 'P.B.S.DISTRIBUTION', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('52275927-e957-4fa8-a459-ab0c18915ce0', 'POOTHANARI FURNITURE & ELECTRONICS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('ec802f21-9ae8-4e08-a7ae-c5ef52baa81f', 'RAJADHANI ELECTRONICS AND HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('72ffe867-63df-4a05-9f50-2f0916449627', 'RAJADHANI FURNITURE & HOME NEEDS KKV', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('1f922a92-15dd-4d7e-8701-8b381ffb6b8a', 'SA Agency Home Appliance', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d61df91a-6086-43ba-b0e7-3fade9408328', 'SHAHID METALS & HOME NEEDS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5381e384-f55a-4da3-b2ab-55f2fca7a32a', 'SHAJAHAN TV&FRIDGE HOUSE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d4509540-2b73-470a-b4ca-353495e829e3', 'Sharafiya Electronics Home Needs', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('bb8f5724-ac68-4687-9d23-e7476bb8211e', 'SREE VINAYA AGENCY', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('28bb1864-a4b6-40e0-a5a2-e92e6e362f61', 'TM HOME APPLIANCES AND FURNITURE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('97cbeb14-0f80-493a-ab23-db0b10ec256d', 'ZODIAC ELECTRONICS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('160b6549-2c49-4046-a7d7-1fcaf0ef6a73', 'AIWA COLLECTION & DISTRIBUTIONS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('967b9347-320f-4987-85e0-c6a23d20a009', 'AMAN FURNITURE & HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('3728c736-0a14-402c-a8d1-76c59526d54d', 'BIG BUY COOLING SOLUTIONS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b41c4b20-1e8c-4221-8efc-1a74f3f51921', 'CHOICE HOME SELECTION (CHAPNGDI)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('30184c61-99d1-414a-ad6c-5dbe3d491320', 'CLASSICO HOME APPLIANCES(Bymnt)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('391debdf-b888-4669-8445-108dac6bf9fe', 'CLASSICO HOME CENTRE (EDPL)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('64a284d8-017f-4244-97b6-26c71740f1e3', 'CLASSICO HOME CENTRE (KTND)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('fc5442d3-4aa5-451e-afa1-f33e210f0ae9', 'CLASSICO HOME CENTRE (VLRY)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('10d7df93-f73e-4cf8-aa30-59aca14953ad', 'CRYSTAL AGENCIES&HOME APPLIANCES(VGA)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d9a34934-ddc9-4fbc-8f7c-85a5c7b186c9', 'CRYSTAL MART HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('6b4aeb2f-0f49-4a42-9f1f-c553573ac637', 'CRYSTAL MART HOME APPLIANCES(New)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('29bd7027-a5d3-47dc-94d6-614aa3240793', 'DIYA FURNITURE & HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('7115f538-d719-412c-bdcf-1235525e3164', 'DUBAI MARKET', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('301ac0d5-d265-487e-87d3-f69dce935cfe', 'Easy installment', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('94b3d974-548c-462e-b218-c5cdbc81ad0a', 'EMARALD AGENCIES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('ae3fde95-927e-47da-aabc-97605baed1fd', 'E WORLD ELECTRONICS AND CROCKERY', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('9e729f36-d69c-45df-b562-ed8432e63bf7', 'E World Home Appliances', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('39630e79-f5fd-4ea6-a50a-1f11c5923e89', 'E ZONE ELECTRONICS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('00df384d-3a1f-4063-8782-e462685078b7', 'FAHIDHA  MOODAL', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f71ada57-b912-48d1-a88e-a60dfc2eeabe', 'HAPPY EMART', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d540d6b0-342a-48f3-9375-7dec6573ae35', 'HOME CENTRE(NEW)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c0bb908e-1016-40f3-b634-91d3836d03bd', 'HOME CITY FURNITURE & HOME APPLIANCE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e24ab17f-c751-45ed-bb20-3da96bb71f2a', 'HOMEZO FURNITURE AND HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('8724a852-743a-46ea-bd4f-d7077994b809', 'HOME ZONE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('6cdbff98-49b9-43d8-a02f-1eaa55a2645d', 'INFRA DIGITAL MART FACTORY OUT LET', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('24a4a36c-617a-4137-b38f-2a770903bedd', 'JAMJOOM SUPER MARKET PRIVATE LIMITED', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('3b45fee0-1cae-46f2-8f90-b73f08145392', 'Kattil Home Appliance', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c38975ad-c2e5-4d1c-a5e5-292b975c8bb4', 'KATTIL HOME APPLIANCE (Pmblpdk)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b62c5377-12a3-4dfe-b52b-ab96e5ea04d0', 'KATTIPARUTHY HOME GUIDE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('76a5e0f1-79be-4be1-a675-67bb51df5ecf', 'KILIYAMANNIL HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('a1d4c145-0147-4da7-8185-dcf23905de1e', 'Linear marketing', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('68c6efb7-f8de-407a-b297-b31166ef63eb', 'M K DIGITAL AND HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('0201be88-683d-4f00-beb8-f009ebab8abf', 'NEXT SHOW HOME APPLIAINCES & ELECTRONICS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b3df6aed-9e80-4f69-ab25-f1bba10a6036', 'OASIS AGENCIES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('6bceecad-5895-474c-97d2-0f20388b7466', 'PARAMMAL HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('05127127-b43f-4147-8d07-96ddec1e0015', 'SANA HOME BAZAR (PUTHANATHANI)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('91acbf99-0d5d-43dc-95fa-6c58edcec1a2', 'SH ELECTRONICS & HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('21a1569d-8818-4669-9035-1abb248e098d', 'S P BUSINESS ASSOCIATES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5e8aaf4e-0900-4f4f-bda4-fa7c461d643b', 'TOP FURNITURE & HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d5987091-e431-4003-afd4-4eba35230673', 'UMMATHIS HOME STYLE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('8b914fae-0176-46fb-a307-c34403e48021', 'UPDATES TRADING LLP', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('ae8e4e27-d6e8-4744-a6f9-2b4dc5aaa0c9', 'WAFA MAHAL HOME APPLIANCES&ELECTRONICS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('86f6d3c5-3d92-4eb2-9e42-5822d00cd5b8', 'WE ELECTRON (Center Bill)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('8474112a-a0cd-4806-8e61-abaf6bc8a12c', 'WE ELECTRON PONNANI', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('949fe9f1-1d95-44bb-bd29-0183210f8da1', 'WHITE HYPERMARKET', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c7490972-3523-46f2-bd80-34a41f07813b', 'ZAIN HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b5918a2f-2036-44f5-a5be-3b14fa3ad81d', 'ABCD ELECTRONICS & HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('72db12da-e232-4a9f-83ae-7868e2e672e8', 'ANJALI ELECTRONICS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('885e0dd0-ce9d-4027-a5f8-7a88dbb98538', 'ARDH SAINIK CANTEEN', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e2cd4cee-7ad1-4243-92ef-69ceb1aea411', 'ARIFA HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('911897a7-c327-42a5-8a19-f41c4f9a42fa', 'AVANI FURNITURES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('66b8b451-65d6-464f-aac0-78ac46b4f7b7', 'AYRIN ENTERPRISES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e8064b7b-44ee-4d16-8d80-bbba052cc759', 'CHENKOTTA FURNITURE &HARDWARES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d86368c6-811a-44fc-9c0a-58b2906483e5', 'Classic Home Appliance', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('36787750-89e6-4daa-8535-e0edf95c91e9', 'CLOUD MOBILES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('386609df-6876-4dcc-bc8f-531f0cd072d1', 'Dreams Home Appliances', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('662407c4-819c-4a9e-8e25-cd9abecae104', 'E1 Electronics,Home Appliances&Mobiles', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b5a3bcac-62f5-43e2-8de5-13e5b4e2771e', 'HOMECENTRE APPLIANCES (PKD)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('cb491a54-c665-42b7-8758-4d01fccbe67c', 'KANKUNNATH HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('de4bd6e4-48b0-4801-b169-a93db1f578e3', 'KOTTARAM HYPER MARKET', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('0e9a5b61-7e9d-4b96-9878-82cc684f7734', 'MAAYON ELECTRONICS AND FURNITURE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('019715c5-b1a3-4a88-a39c-dbf3bc6a3807', 'MALABAR BAZAR', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('8ac2d235-a916-4a6a-afd2-75d2cdc0b849', 'MALABAR METRO', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('bcac8418-8969-4191-b4b0-31181d9380b4', 'MARHABA FURNITURE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('4424c5e3-44a3-4413-b916-1c8752a10bb9', 'Maria Home Appliance', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('4b937444-4d93-4e1c-bee6-b6d72553c3e9', 'MAXPLUS DIGITAL AND HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('425bf357-82e3-4610-9ae7-8ef861529346', 'Melco Eletrical Super Market', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('9969ef7a-cc90-459f-8b6e-72da3835d1e0', 'MELCO MYHOME', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f5618c6c-78ad-4b9e-be9f-909b7d0c74c8', 'Melco the Electrical and Home World', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('1547a46f-d63b-4e94-99ee-7ff966a70619', 'MELCO TRADE CENTRE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('2d28d527-3b14-4b24-9b44-7ee55f056e40', 'MOHAN TV SALES & SERVICE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('1dc153db-ac06-4176-91e9-5c158be875f8', 'MUBARAQ  Elecronics&Home Appliances', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('a40e80c0-d5d2-4f39-9812-c9740153e295', 'MUBARAQ HOME SHOPPE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('1e139c27-357e-443d-b71e-b2a83f9c0b6d', 'MUBARAQ T.V Show Room', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e57b1c2e-1f16-4025-85fb-c0ebfbdeb13f', 'Mubeena Furniture and Home Applinces', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('352503f6-534a-4ee0-a0f1-c0bd7ba50422', 'MULLAKKAL HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e719cdd8-426e-4eee-be91-812c354af391', 'MULLAS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('6baf344a-1812-491f-9a6f-10053abe2bc9', 'NALAKATH AGENCIES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('9feb4181-c32e-4cd4-b91d-1dc7b24249cf', 'NANDHANA ELECTRONICS&HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('67363692-183e-453d-b621-7e2d8375846f', 'Neerkarakkat Agencies', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('4a5c1dd3-8929-4e6b-a0e2-1f2068e5928f', 'New India Home Appliances', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('6d2267c7-1d65-4fd0-9e15-53e2b7f16e05', 'NEW MALABAR HOME APPLIANCE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('2912c98b-4c72-4448-b983-76ccc4fd4c7e', 'PAK ENTERPRISES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('9a6988cc-e4ed-49ee-95fc-633d470bf61e', 'PH DIGITAL HUB', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('ee47cd51-ec0a-43d0-b4af-d258928f3859', 'PH MOBILES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5c919c2e-8949-4a24-ad20-1a2374cb8501', 'P K ELECTRONICS&HOME NEEDS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('00273731-140f-45b4-a0fc-b5dbeb9296ee', 'P T M FURNITURE MANGODE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('eb8df156-540b-4bad-b9fc-5da98a74e20f', 'REGAL HOME APPLIANCES NEW', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('cfb6680a-ca41-4dee-97ee-6f941dd8fc45', 'RV HOME NEEDS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('39683a69-a1b9-43ef-a38c-5f7ee780278c', 'SREE LAKSHMI AGENCIES (PKD)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b9280248-12b7-4777-b954-6d3c9ea57896', 'STAR VALUE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b92a88b5-545d-43c3-a0b1-ebefc01397bf', 'TECNO LAND', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('13fbbbc6-c5ff-472a-8071-32334298c7e0', 'THEKKEKUTTU AGENCIES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('ee42dca1-fd90-4bf3-ab53-407d3d6d7dd2', 'VEMMARATHIL ELECTRONICS AND HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('52d2a626-6ad9-4d6b-84d0-0a6738a8158d', 'VERTEX MARKETING', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('42d2b7f8-b889-4257-af80-a0c69690bd31', 'Vrindavan Home Appliances', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('4aa4c2cb-554e-4fc8-a64b-65797ea8409a', 'Air Cool Shoppe', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('ebf23027-fae4-4fdd-87ce-0c04dbe53362', 'AMAZE ASSOCIATES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('9ed2aac9-720b-4a1f-87fd-4df257d3b508', 'ASSOCIATED COMPUTERS AND SECURITY SOLUTIONS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('531120bc-ddfc-4de9-be55-ff3ada1704f1', 'BEST HOME APPLIANCES (PDKL)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('3820f67f-5af1-483f-b1b6-ecaa7565fc88', 'CHOICE HOME COLLECTIONS (PTNTNI)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('20843723-3231-47b2-845d-492c3b4f3e1a', 'CK ASSOCIATES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('3ad3f6cf-2a9f-4bab-8f2d-c7f59c23a61a', 'COOL LINE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b457cd00-1311-4063-929f-9ada9bdc1b42', 'EMINENT ELECTRICALS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('91a54a85-4949-413b-9529-65635e6762a5', 'FLASH ELECTRONICS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f44ce545-7565-42d5-b2ac-05be7a356f1f', 'GRAND E MART', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('701808df-c64f-460d-a416-56154839818b', 'JUMBO ELECTRICAL TRADERS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('7715565d-29e5-4231-8f78-bfc10975312a', 'KK MOIDEEN AND SON', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('6bc1a59f-415e-49cc-8199-7e070d29bf97', 'KOHINOOR ELECTRONICS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('2dd95d9a-f493-4869-9912-d7a8e82bbf4b', 'LIFE KART (PTNGDI)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b67af78d-759d-4cdd-b0c2-f8ba4d432cd8', 'MEPARAMBATH TRADERS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('0555f13e-dfa3-4b24-a1bf-dac9e3e31c06', 'MY MART DIGITAL ELECTRONICS & HOME APPLIANCES (KDV)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c5643ff1-0af7-4166-a2a1-b213ce8f2972', 'NEW ZAHEER ELECTRONICS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f327f63e-6583-42e9-9998-bd99060c080d', 'RAFEEQUE HOME CENTER', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d795abb2-495b-43eb-b611-58ae894d7a51', 'REAL HOME CENTRE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f6bf6f98-19d5-4860-9c2f-e3201749ef2d', 'SAI TRADERS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('8b71a912-7934-4d33-b2e3-d6be4724e726', 'TAJ HOME APPLAINCES & FURNITURE', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('22468c49-0327-4994-8c5c-62b4676b572e', 'TEEKAY HOMEAIDS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('cc18584f-bfaf-4599-827e-eb2d9ac4aa93', 'THAHIRA HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('7daf1ab6-becd-47fa-bcdf-8d7b92a5a11c', 'TRIVENI HOME APPLAINCES AGENCIES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('43b0f79f-97b4-49c8-bb9d-2c8c5e3d9f5d', 'UNITED BUSINESS CORPORATION (UBC)', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('9a801072-07a5-40b4-ad71-897bfb20eef3', 'VEE KEY HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('81eabae1-5d24-41d8-ab0a-ea083fcd931c', 'WE ELECTRON', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('86364ad7-8faa-42a1-877b-d015a31cc230', 'ZAHEER ELECTRONICS', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('42d55ea5-2d59-47f8-92e1-d5b0563bd6e8', 'Zaheer Enterprises', NULL, NULL, true, '2026-10-08 15:56:28.770661+05:30', '2026-10-08 15:56:28.770661+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('4ae69fc8-3263-43c8-b9a3-406e01e3c624', 'Akam Home Appliances&Mobiles(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('578105e8-a068-429f-8dca-aa3667bbb020', 'Amal Cool Air Conditioners(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5c87318f-7f70-4269-9b8b-a16aba651fab', 'ASCO ENGINEERSCR(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b7c3d268-3df5-4494-adbe-01e89d73b10e', 'ASSOCIATED COMPUTERS AND SECURITY SOLUTIONS (CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('8b5038ae-b6e8-4692-a3f6-62a158b61338', 'B S AGENCY(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5c6fed18-d243-481a-8021-d105dcb9b751', 'DIGITAL MART (CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('a026839a-a89f-4c82-b44b-4ceb84ba6566', 'EVERCOOL REFRIGERATION &AIR CONDITION(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5e351554-8dd4-47bb-8cad-ab4c16486c83', 'EXCEL APPLIANCES AND AIR CONDITIONS (CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('43aae77d-7a53-4af8-aef0-59b1839bc9ca', 'FRIDGE HOUSE(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('acff8543-d2a4-4766-9fb3-32130e694192', 'Friends Computers Home Appliances(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('786dfb76-f1c6-46f3-a8ae-0815aac1cb0f', 'G CONNECT(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('8668693e-0d33-4375-9d38-d7af56948f66', 'HOME CHOICE WANDOOR(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c7ed8a02-d41d-4ee8-916d-5af094e42820', 'INFRA DIGITAL MART FACTORY OUTLET(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('0402117a-c498-44a0-bb80-76bdb510fc87', 'KALYANI E MART(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('0f1b58f9-5240-4d2c-8ee4-c3b40ea2ac47', 'KMK Electronics & Home Appliances( CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('8e93c528-f917-4de4-a59f-36936a9e9682', 'MARVEL APPIANCES (CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('8093664c-f282-4653-bf38-618524c3c521', 'NEW WAY CENTER (CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('db5f5a68-8825-46da-9415-b66659c22b8f', 'SHAJAHAN TV& FRIDGE HOUSE (CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('777f0154-88c9-4ca1-8d8f-5c2f6200d043', 'SIGMA ELECTRONICS & HOME BAZAR NLMBR(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('cf38443e-f73b-4376-9200-42348af2581b', 'STANTECH TRADING LLP(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('302d2015-1bad-4edf-953a-42aebf3778a7', 'SUPREME KOTTAKKAL (CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('559d76a2-3c74-4fac-b32f-de23a8a99dcb', 'TECHNO COOL(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('a6fec96f-f65b-491f-a3b2-be13c4d57191', 'TOP FURNITURE AND HOME APPLIANCES(CR)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c9e455ae-1f65-4c84-a970-0700416ebd7d', 'Akam Home Appliances & Mobiles', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5ee242de-1a74-41a4-8f9e-0453a428314d', 'Associated Computers and Security Solutions (Fmty)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('19372813-b1d3-4732-86df-f75ea2ccc1bb', 'AYISHA KUTTY', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('356bafe6-5f2e-4c9b-91d2-ee8d78c877f2', 'B & M 2 INTERNATIONAL INVESTMENT GROUP', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('0a9e71e2-8a8d-49a7-81d0-45690fd82f8e', 'Choice Home Selection (Chapanangadi)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('31ba9ab2-8716-47d3-9316-b960d8530ee7', 'CITY CHOICE CMD (F)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('47611cc8-c515-43d6-9f3b-38d9eea16fdb', 'CLASSICO HOME CENTRE(EDPL)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('58778c81-9ac8-4bda-bbc0-8aa1d0fcb488', 'Cool Land Tirur', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('8fe74a49-554b-481e-8c67-16e8d51df326', 'COOL MART HOME APPLIANCES (NEW)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b9c2380d-e466-4651-90b6-b360e91bdb77', 'DIGITAL MART (AKD)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f8cbcb35-4fb4-4c16-b324-99f951900b64', 'Friends Computers Home Appliances', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('2adea84b-cff6-4e89-a38b-1b95ce951bbf', 'Glockery Home Centre', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e88d9d17-5b1a-4c65-a32a-47483f250ce5', 'Home Land Home Needs', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('0c503476-c680-4506-a19e-2c67ac2bc2ea', 'HOMEZO FURNITURE AND HOME APPLIANCES (FMTY)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('3f36d1f5-5a77-4c54-bd7a-5c977cbc4f2b', 'KATTIL HOME APPLIANCE(Pmbipdk)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f1094384-a06e-4a3c-bbfc-e81d42dc2ecc', 'Kk Moidheen & Son', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('103536b0-a99f-4ad6-b4db-3dc49fb058b1', 'KMK Electronics & Home Appliances', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('065e0926-b0b9-4d38-b39b-93ce75b16f07', 'KRIPA HOME APPLIACES', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('2385c7ae-7531-41c0-b1ad-c575fbbc069f', 'Sana Home Bazar(Puthanathani)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('a24110aa-64db-4499-b3c5-2b4a9c5638da', 'Shajahan TV & Fridge House', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f37ab5b3-8a3b-4643-bec2-6002a162bfe2', 'THAYYIL HOME CENTER', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('cc6e190b-b8f3-4403-a922-44b15c4117c1', 'Vee Key Home Appliaces', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('8b03eeb3-379c-41af-bfd4-e7255716218a', 'AERONEX COOLING SOLUTION(New)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('11aad461-54db-48e2-b0f4-4a3348bcac05', 'ASSOCIATED ELECTRONICS', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f7a749f0-8f35-4205-bb99-963ae640ecf9', 'Benzy Home Makers Pvt Ltd', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('4502a854-719d-4b41-9db3-52e056eacb65', 'BigBuy Airconditioning Engineers', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('2689c076-a005-4c9a-b37c-a2db64880e0c', 'BigBuy Airconditioning Engineers (Vngara)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('562eae73-071a-40a9-a3be-a24482d0c907', 'Brand Store', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e1498b8d-7149-4e6e-8afb-90276f96a16f', 'Breezy Homes', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('17235086-f57e-4c25-a4dc-1bc2b0bb7fe5', 'City Choice Chemad', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f6686b31-f209-44a6-8c06-97604d2a96d6', 'CITY CHOICE VALANCHERY', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('cfaedd84-4b2e-4368-9a3a-bc38ac07ba4f', 'Continental Designer Pavers', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5d7e3161-054a-446c-add2-6faed89bd0e2', 'COOL DAY AGENCIES', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('ac74d81c-b9a1-415e-9e98-81efcc3de4e7', 'CRYSTAL AGENCIES & HOME APPLIANCES (VGA)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f0800d98-a466-4087-b7b1-9834b9f349fe', 'Day Night Air Conditioners', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c3ac1578-1f5f-42df-97c2-2bf9627d8421', 'DIGI SOLAR SOLUTION', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c39623ad-efe9-4aa1-b9ac-1117c920c6cc', 'DIGITAL MART (Kvnr) F', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('ac48bae2-6999-40ce-a6ac-d90fae619ea7', 'Evercool Refrigeration and Aircondition', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('18f6a4a7-b58d-4033-8465-dd3fce65f83e', 'Freeze World', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c880574c-3949-4e22-9800-b58b3153e0a0', 'Hom Q Digital Electronics & Home', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('fe84dbc1-b3f8-4b06-9470-ccec92bda03c', 'Indian Electronics (Chelari)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('1dfce754-1156-44c1-818d-cea81d550353', 'KALPAKA ELECTRONICS & HOME BAZAR KDY', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f72268cf-30c0-43d4-9470-447f6c2c01d5', 'KATTIL HOME APPLIANCE  PRMBIL(OG)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('8fbba9ca-3a88-4e1d-9fac-3a230b945d3b', 'KMK ELECTRONICS&HOME APPLIANCES(G)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('9dcb8f6a-193c-4bae-a44f-858a189c7875', 'LIFE HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('963649ef-f9c6-412a-93e8-bd81fd28f688', 'Malabar Enterprises', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b6fe2adb-7fcb-4101-be42-c6ad33bfd11a', 'Master Cools Sales and Services', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('505c41a7-a6d0-408d-8aee-9b4a1386517f', 'Master Cools Sales & Services', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b29913f1-3602-4879-ae33-fd5a75da8586', 'MEPARAMBATH TRADERS (NADUVATTOM)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('e23ff15c-056a-4257-a798-320a3dc80a05', 'M G AGENCIES', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f97eaf29-6224-4579-a8f2-0789c6b208a3', 'Mia Cooling System', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('188c2a66-66dd-4b90-954c-0d011a3a9571', 'Muhammed Salih.P', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('c06cb53a-6a22-43cb-b3c6-bea163cfa9c7', 'NEW WAY CENTER', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('f5b85c11-3a3f-4e9b-a4d3-a68f52fdf569', 'Pazheri Cooling System', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('fb1b30d4-f29c-4a4c-9ee9-20253ea0f592', 'PRICE HVAC INTEGRATORS', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('93ae95c5-1dc6-49c1-a9bb-d5c8668108f0', 'Regal Home Appliances Koppam', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('653341e2-c005-4613-b1fe-8b276973f24e', 'SANA HOME BAZAR (Og)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('b3ee1119-3133-40ed-b6d1-ab248fdd7ebb', 'Sigma Electronics Gallary Edavanna', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('0b3a5d2b-37f2-4ad0-88a3-64342e96208c', 'SIGMA ELECTRONICS & HOME BAZAR NLMBR', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('39d64f4a-10ee-4db9-b913-02105a347abd', 'Sigma Electronics  Mnjri', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5538dce5-f364-4cc6-a615-ab32c039b728', 'Stan Tech MEP Solution', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('94ad2022-bfc6-4a0f-a822-d214a8569d41', 'STANTECH TRADING LLP', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5f248934-ff8a-4bca-ad48-c3d988db1678', 'TEEKAY  HOMEAIDS', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d6f048b0-757a-46d6-bedd-2ac948581a83', 'ULTRA COOL(CLT)', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('a3ab4d6b-bc24-45e3-be8a-06c4ebf36a71', 'Valappil Home Style Pvt Ltd', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('5301bc9d-9158-4e80-9ace-94df0d4dc4d9', 'CRYSTAL HOME APPLIANCES', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('173a1f19-832b-42ed-ac32-6687c057e865', 'MALABAR PLUS', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('d37e8f4e-88d5-47ca-b238-191d95cf279c', 'MUBARAQ Electronics&Home Appliances', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');
INSERT INTO public.shops (id, name, city, phone, is_active, created_at, updated_at) VALUES ('46f102a1-e4d7-45c0-9823-f9b08438314a', 'P K ELECTRONICS& HOME NEEDS', NULL, NULL, true, '2026-10-08 15:56:49.875827+05:30', '2026-10-08 15:56:49.875827+05:30');


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.users (id, username, full_name, password_hash, role, is_active, created_at, updated_at) VALUES ('656f2005-9e50-4d61-9009-e9356e0a9c46', 'admin', 'System Administrator', '$argon2id$v=19$m=65536,t=3,p=4$BqDUOuec09o7h/Cek9I6Rw$JV3hJkB8V1wsQLggAUuLLkxfPbkClgMLTLj/vbjRSMU', 'admin', true, '2026-10-07 16:42:49.04992+05:30', '2026-10-07 16:42:49.04992+05:30');
INSERT INTO public.users (id, username, full_name, password_hash, role, is_active, created_at, updated_at) VALUES ('1c32c290-0657-489b-adea-935fbe2d6659', 'staff', 'Warehouse Staff', '$argon2id$v=19$m=65536,t=3,p=4$F4KwllLq3VsrZayVMmasFQ$C3i8v70G7yyzZC877CFZVjaRAys0YX3MvkbgYBJxqho', 'staff', false, '2026-10-07 16:48:15.168029+05:30', '2026-10-07 16:50:54.470285+05:30');
INSERT INTO public.users (id, username, full_name, password_hash, role, is_active, created_at, updated_at) VALUES ('433ebcc8-1377-4432-a88a-9b155a534784', 'shihab', 'Shihab', '$argon2id$v=19$m=65536,t=3,p=4$0BpjzHmPcc7ZG6P0/l/LeQ$p/XXUK7pTZ809yCCIP3cYqRaioVWIhz09VKI+b9efug', 'staff', true, '2026-10-07 16:51:25.668739+05:30', '2026-10-08 13:15:02.517058+05:30');


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


