-- ============================================================================
-- OneDoc — Multi-User Collaboration Migration
-- Run this in your Supabase SQL Editor AFTER the initial migration
-- ============================================================================

-- ============================================================================
-- 1. DROP OLD RESTRICTIVE POLICIES
-- ============================================================================
DROP POLICY IF EXISTS "projects_select" ON projects;
DROP POLICY IF EXISTS "projects_insert" ON projects;
DROP POLICY IF EXISTS "projects_update" ON projects;
DROP POLICY IF EXISTS "projects_delete" ON projects;

-- ============================================================================
-- 2. NEW SHARED-ACCESS POLICIES
-- All authenticated users can read and edit any project.
-- Only the project owner or an admin can delete.
-- ============================================================================

-- SELECT: any authenticated user can see all projects
CREATE POLICY "projects_select" ON projects
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- INSERT: any authenticated user can create projects
CREATE POLICY "projects_insert" ON projects
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- UPDATE: any authenticated user can update any project
CREATE POLICY "projects_update" ON projects
  FOR UPDATE USING (auth.uid() IS NOT NULL);

-- DELETE: only the owner OR an admin can delete
CREATE POLICY "projects_delete" ON projects
  FOR DELETE USING (
    owner_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role = 'admin'
    )
  );

-- ============================================================================
-- 3. ADD last_edited_by COLUMN (tracks who last touched the project)
-- ============================================================================
ALTER TABLE projects
  ADD COLUMN IF NOT EXISTS last_edited_by UUID REFERENCES auth.users(id);

-- ============================================================================
-- 4. ENABLE REALTIME on the projects table
-- This allows Supabase Realtime subscriptions for live collaboration.
-- ============================================================================
ALTER PUBLICATION supabase_realtime ADD TABLE projects;

-- ============================================================================
-- 5. MAKE YOUR USER AN ADMIN
-- Replace the email below with your actual admin email, then run this.
-- You can add more admins the same way.
-- ============================================================================
UPDATE profiles SET role = 'admin' WHERE email = 'sreed@pearsonpkg.com';
