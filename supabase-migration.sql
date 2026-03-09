-- ============================================================================
-- OneDoc — Supabase Migration Script
-- Run this in your Supabase SQL Editor (supabase.com > your project > SQL Editor)
-- ============================================================================

-- ============================================================================
-- 1. PROFILES (extends Supabase auth.users)
-- ============================================================================
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  email TEXT,
  role TEXT DEFAULT 'user',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Auto-create profile when a user signs up
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', NEW.raw_user_meta_data ->> 'name', ''),
    NEW.email
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================================================
-- 2. PROJECTS (top-level container — one row per OneDoc project)
-- Stores the ENTIRE form state as a single JSONB blob for simplicity.
-- This avoids the complexity of 10+ normalized tables while still giving
-- you full query capability via JSONB operators.
-- ============================================================================
CREATE TABLE IF NOT EXISTS projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  project_name TEXT NOT NULL DEFAULT 'Untitled Project',
  customer_name TEXT DEFAULT '',
  opportunity_number TEXT DEFAULT '',
  created_by TEXT DEFAULT '',
  tags TEXT[] DEFAULT '{}',
  version INTEGER DEFAULT 1,
  form_data JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Index for faster lookups
CREATE INDEX IF NOT EXISTS idx_projects_owner ON projects(owner_id);
CREATE INDEX IF NOT EXISTS idx_projects_updated ON projects(updated_at DESC);

-- ============================================================================
-- 3. CUSTOM MACHINES (shared machine registry)
-- ============================================================================
CREATE TABLE IF NOT EXISTS custom_machines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  machine_data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================================
-- 4. ROW LEVEL SECURITY
-- ============================================================================

-- Enable RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE custom_machines ENABLE ROW LEVEL SECURITY;

-- PROFILES: users can read all profiles, update only their own
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (true);
CREATE POLICY "profiles_update" ON profiles FOR UPDATE USING (id = auth.uid());
CREATE POLICY "profiles_insert" ON profiles FOR INSERT WITH CHECK (id = auth.uid());

-- PROJECTS: users can only CRUD their own projects
CREATE POLICY "projects_select" ON projects FOR SELECT USING (owner_id = auth.uid());
CREATE POLICY "projects_insert" ON projects FOR INSERT WITH CHECK (owner_id = auth.uid());
CREATE POLICY "projects_update" ON projects FOR UPDATE USING (owner_id = auth.uid());
CREATE POLICY "projects_delete" ON projects FOR DELETE USING (owner_id = auth.uid());

-- CUSTOM MACHINES: all authenticated users can read; creator can manage
CREATE POLICY "machines_select" ON custom_machines FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "machines_insert" ON custom_machines FOR INSERT WITH CHECK (created_by = auth.uid());
CREATE POLICY "machines_update" ON custom_machines FOR UPDATE USING (created_by = auth.uid());
CREATE POLICY "machines_delete" ON custom_machines FOR DELETE USING (created_by = auth.uid());

-- ============================================================================
-- 5. STORAGE BUCKETS (for PDF/Excel exports and file uploads)
-- ============================================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('exports', 'exports', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies: users can manage their own folder
CREATE POLICY "exports_insert" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'exports' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "exports_select" ON storage.objects FOR SELECT
  USING (bucket_id = 'exports' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "exports_delete" ON storage.objects FOR DELETE
  USING (bucket_id = 'exports' AND (storage.foldername(name))[1] = auth.uid()::text);

-- ============================================================================
-- 6. UPDATED_AT TRIGGER (auto-update timestamp on modifications)
-- ============================================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS projects_updated_at ON projects;
CREATE TRIGGER projects_updated_at
  BEFORE UPDATE ON projects
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS profiles_updated_at ON profiles;
CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS custom_machines_updated_at ON custom_machines;
CREATE TRIGGER custom_machines_updated_at
  BEFORE UPDATE ON custom_machines
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
