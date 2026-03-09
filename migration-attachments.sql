-- ============================================================================
-- OneDoc — File Attachments Migration
-- Run this in your Supabase SQL Editor AFTER the multi-user migration.
--
-- IMPORTANT: After running this SQL, you must ALSO create the storage bucket
-- manually in the Supabase Dashboard:
--   1. Go to Storage in the left sidebar
--   2. Click "New Bucket"
--   3. Name it exactly: project-files
--   4. Toggle ON "Public bucket"
--   5. Click "Create bucket"
--
-- Then add these Storage Policies for the bucket (Storage > Policies):
--   - INSERT: allow authenticated users  (auth.uid() IS NOT NULL)
--   - SELECT: allow everyone              (true)  — public reads
--   - DELETE: allow authenticated users   (auth.uid() IS NOT NULL)
-- ============================================================================

-- ============================================================================
-- 1. PROJECT ATTACHMENTS TABLE
-- Tracks file metadata per project. The actual files live in Supabase Storage.
-- ============================================================================
CREATE TABLE IF NOT EXISTS project_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE NOT NULL,
  uploaded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  file_name TEXT NOT NULL,
  file_size BIGINT DEFAULT 0,
  content_type TEXT DEFAULT '',
  storage_path TEXT NOT NULL,       -- path inside the 'project-files' bucket
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_attachments_project ON project_attachments(project_id);
CREATE INDEX IF NOT EXISTS idx_attachments_created ON project_attachments(created_at DESC);

-- ============================================================================
-- 2. ROW LEVEL SECURITY
-- Matches the shared-access pattern: any authenticated user can read/add,
-- only the uploader or an admin can delete.
-- ============================================================================
ALTER TABLE project_attachments ENABLE ROW LEVEL SECURITY;

-- SELECT: any authenticated user can see all attachments
CREATE POLICY "attachments_select" ON project_attachments
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- INSERT: any authenticated user can upload
CREATE POLICY "attachments_insert" ON project_attachments
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- DELETE: only the uploader or an admin can remove
CREATE POLICY "attachments_delete" ON project_attachments
  FOR DELETE USING (
    uploaded_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role = 'admin'
    )
  );

-- ============================================================================
-- 3. UPDATED_AT on projects when attachments change (optional)
-- Touch the parent project's updated_at so realtime subscribers get notified.
-- ============================================================================
CREATE OR REPLACE FUNCTION touch_project_on_attachment_change()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE projects SET updated_at = now() WHERE id = OLD.project_id;
    RETURN OLD;
  ELSE
    UPDATE projects SET updated_at = now() WHERE id = NEW.project_id;
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS attachment_touch_project ON project_attachments;
CREATE TRIGGER attachment_touch_project
  AFTER INSERT OR DELETE ON project_attachments
  FOR EACH ROW EXECUTE FUNCTION touch_project_on_attachment_change();
