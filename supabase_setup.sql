-- ============================================================
-- City Guest — Unified Supabase Database Schema Script
-- Run this in Supabase SQL Editor (Project > SQL Editor)
-- ============================================================

-- 1. Enable UUID Extension
create extension if not exists "uuid-ossp";

-- 2. Profiles Table (extends auth.users)
create table if not exists public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  name text not null,
  email text not null,
  role text not null check (role in ('super_admin', 'sub_admin')) default 'sub_admin',
  is_active boolean default true,
  created_at timestamptz default now()
);

-- 3. Guest Visits Table
create table if not exists public.guest_visits (
  id uuid default uuid_generate_v4() primary key,
  guest_name text not null,
  phone_number text not null,
  occupation text,
  photo_url text,
  place text not null,
  district text not null,
  state text,
  country text,
  is_international boolean default false,
  purpose text not null,
  donation_amount numeric default 0,
  receipt_no text,
  picked_from text,
  picked_date date,
  picked_time text,
  guest_returned text,
  return_date date,
  return_time text,
  handled_by text,
  remarks text,
  pdf_url text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

-- 4. Visited Places Table
create table if not exists public.visited_places (
  id uuid default uuid_generate_v4() primary key,
  guest_visit_id uuid references public.guest_visits(id) on delete cascade not null,
  visited_place text not null,
  visit_date date,
  time_in text,
  time_out text,
  sort_order integer default 0
);

-- 5. Events Table
create table if not exists public.events (
  id uuid default uuid_generate_v4() primary key,
  event_name text not null,
  event_place text not null,
  members_count integer not null default 0,
  organized_by text not null,
  event_date date not null,
  handled_by text not null,
  remarks text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

-- 6. Guest Assignments Table
create table if not exists public.guest_assignments (
  id uuid default uuid_generate_v4() primary key,
  guest_name text not null,
  notes text,
  assigned_to uuid references public.profiles(id) on delete cascade not null,
  assigned_by uuid references public.profiles(id) on delete set null not null,
  status text not null check (status in ('pending', 'in_progress', 'completed')) default 'pending',
  due_date date,
  is_urgent boolean default false,
  created_at timestamptz default now()
);

-- 7. App Notifications Table
create table if not exists public.app_notifications (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references public.profiles(id) on delete cascade not null,
  title text not null,
  message text not null,
  type text check (type in ('info', 'urgent', 'reminder')) default 'info',
  is_read boolean default false,
  created_at timestamptz default now()
);

-- 8. Enable RLS
alter table public.profiles enable row level security;
alter table public.guest_visits enable row level security;
alter table public.visited_places enable row level security;
alter table public.events enable row level security;
alter table public.guest_assignments enable row level security;
alter table public.app_notifications enable row level security;

-- 9. Security Definer helper to prevent RLS recursion
create or replace function public.is_super_admin()
returns boolean as $$
  select coalesce((select role from public.profiles where id = auth.uid()) = 'super_admin', false);
$$ language sql security definer stable;

-- 10. Clean Non-Recursive Policies
drop policy if exists "Profiles select policy" on public.profiles;
drop policy if exists "Profiles update policy" on public.profiles;
create policy "Profiles select policy" on public.profiles for select using (id = auth.uid() or public.is_super_admin());
create policy "Profiles update policy" on public.profiles for update using (id = auth.uid() or public.is_super_admin());

drop policy if exists "Guest visits select policy" on public.guest_visits;
drop policy if exists "Guest visits insert policy" on public.guest_visits;
drop policy if exists "Guest visits update policy" on public.guest_visits;
drop policy if exists "Guest visits delete policy" on public.guest_visits;
create policy "Guest visits select policy" on public.guest_visits for select using (created_by = auth.uid() or public.is_super_admin());
create policy "Guest visits insert policy" on public.guest_visits for insert with check (created_by = auth.uid() or public.is_super_admin());
create policy "Guest visits update policy" on public.guest_visits for update using (created_by = auth.uid() or public.is_super_admin());
create policy "Guest visits delete policy" on public.guest_visits for delete using (created_by = auth.uid() or public.is_super_admin());

-- 11. Storage Bucket Creation
insert into storage.buckets (id, name, public)
values ('guest-pdfs', 'guest-pdfs', true)
on conflict (id) do nothing;
