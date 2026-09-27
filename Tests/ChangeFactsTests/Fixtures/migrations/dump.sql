--
-- PostgreSQL database dump
--

DROP TABLE IF EXISTS public.users;
DROP TABLE IF EXISTS public.sessions;
DROP TABLE IF EXISTS public.orders;
CREATE TABLE public.users (id integer NOT NULL, email text);
CREATE TABLE public.sessions (id integer NOT NULL);
CREATE TABLE public.orders (id integer NOT NULL);
